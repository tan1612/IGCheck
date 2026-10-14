class ParsedAccount {
  final String username;
  final String password;
  final String twoFactorKey;
  final String cookie;
  final String email;
  final String emailPassword;
  final String rawLine;

  const ParsedAccount({
    this.username = '',
    this.password = '',
    this.twoFactorKey = '',
    this.cookie = '',
    this.email = '',
    this.emailPassword = '',
    this.rawLine = '',
  });

  bool get hasCookie => cookie.trim().isNotEmpty;
  bool get hasTwoFactor => twoFactorKey.trim().isNotEmpty;
  bool get hasPassword => password.trim().isNotEmpty;
  bool get hasEmail => email.trim().isNotEmpty;

  @override
  String toString() {
    return 'ParsedAccount(user: $username, pass: ${password.isNotEmpty ? "***" : ""}, 2fa: ${twoFactorKey.isNotEmpty ? "yes" : "no"}, cookie: ${cookie.isNotEmpty ? "yes" : "no"})';
  }
}

class AccountParserHelper {
  /// Checks if a string segment is a cookie string
  static bool isCookie(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;

    // Check common cookie key names
    final lower = t.toLowerCase();
    if (lower.contains('c_user=') ||
        lower.contains('xs=') ||
        lower.contains('datr=') ||
        lower.contains('sb=') ||
        lower.contains('ds_user_id=') ||
        lower.contains('sessionid=') ||
        lower.contains('ig_did=') ||
        lower.contains('csrftoken=') ||
        lower.contains('fr=')) {
      return true;
    }

    // Match generic cookie pattern key=val; key2=val2
    if (t.contains(';') && t.contains('=')) {
      final pairCount = t.split(';').where((s) => s.contains('=')).length;
      if (pairCount >= 2) return true;
    }

    return false;
  }

  /// Checks if a string segment is a Facebook Access Token (e.g. EAAAA..., EAAB..., etc.)
  static bool isToken(String text) {
    final t = text.trim();
    return (t.startsWith('EAA') || t.startsWith('EAAB') || t.startsWith('EAAG') || t.startsWith('EAAY')) && t.length > 35;
  }

  /// Checks if a string is a 2FA secret key
  static bool isTwoFactorKey(String text) {
    final t = text.replaceAll(' ', '').trim();
    if (t.length < 14 || t.length > 64) return false;
    if (t.contains('=') || t.contains(';') || t.contains('@') || t.contains('/') || t.contains('\\')) {
      return false;
    }
    if (isToken(t) || isCookie(t) || isEmail(t)) return false;
    // Pure digit string is a UID or phone number, never a 2FA secret key
    if (RegExp(r'^\d+$').hasMatch(t)) return false;
    // Lowercase strings (or containing lowercase letters) are usernames or passwords (e.g. andratrevino177172, johnapfohl477852).
    // Real 2FA secrets exported for FB/IG are Base32 uppercase strings (A-Z, 0-9).
    if (RegExp(r'[a-z]').hasMatch(t)) return false;
    // Allow A-Z and 0-9 (some sellers or tools format 2FA keys with 0 or 1)
    final regex = RegExp(r'^[A-Z0-9]+$');
    return regex.hasMatch(t);
  }

  /// Checks if a string is an email address
  static bool isEmail(String text) {
    final t = text.trim();
    if (!t.contains('@') || !t.contains('.')) return false;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(t);
  }

  /// Extracts UID from cookie string (c_user or ds_user_id)
  static String? extractUidFromCookie(String cookie) {
    final cUserMatch = RegExp(r'c_user=(\d+)').firstMatch(cookie);
    if (cUserMatch != null) return cUserMatch.group(1);

    final dsUserMatch = RegExp(r'ds_user_id=(\d+)').firstMatch(cookie);
    if (dsUserMatch != null) return dsUserMatch.group(1);

    return null;
  }

  /// Extracts only the cookie portion from any text (single cookie or UID|PASS|2FA|COOKIE)
  static String? extractCookieOnly(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    if (isCookie(trimmed) && !trimmed.contains('|')) {
      return trimmed;
    }

    if (trimmed.contains('|')) {
      final parts = trimmed.split('|');
      for (final p in parts) {
        final pTrim = p.trim();
        if (isCookie(pTrim)) {
          return pTrim;
        }
      }
    }

    // Fallback: regex search for c_user, ds_user_id, sessionid, csrftoken cookie pattern
    final regex = RegExp(r'((?:c_user|datr|sb|xs|ds_user_id|sessionid|csrftoken|ig_did)=[^|\r\n\t]+)');
    final match = regex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)?.trim();
    }

    return null;
  }

  /// Smartly parses a single line into a [ParsedAccount]
  static ParsedAccount parseLine(String line) {
    final clean = line.trim();
    if (clean.isEmpty) return const ParsedAccount();

    // Check if the entire line is a cookie
    if (!clean.contains('|') && isCookie(clean)) {
      final uid = extractUidFromCookie(clean) ?? '';
      return ParsedAccount(
        username: uid,
        cookie: clean,
        rawLine: clean,
      );
    }

    // Check delimiter: pipe '|' or tab '\t'
    String delimiter = '|';
    if (!clean.contains('|') && clean.contains('\t')) {
      delimiter = '\t';
    }

    final rawSegments = clean.split(delimiter).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (rawSegments.isEmpty) return const ParsedAccount();

    String detectedUsername = '';
    String detectedPassword = '';
    String detectedTwoFactor = '';
    String detectedCookie = '';
    String detectedEmail = '';
    String detectedEmailPass = '';

    final unassigned = <int, String>{};

    int startIndex = 0;
    // If the first segment is not a cookie, it is always the username (UID, IG handle, email)
    if (!isCookie(rawSegments[0])) {
      detectedUsername = rawSegments[0];
      startIndex = 1;
    }

    int emailIndex = -1;
    for (int i = startIndex; i < rawSegments.length; i++) {
      final seg = rawSegments[i];

      if (detectedCookie.isEmpty && isCookie(seg)) {
        detectedCookie = seg;
      } else if (isToken(seg)) {
        // Facebook access tokens (EAAAA...) should not be treated as password or email password
        continue;
      } else if (detectedEmail.isEmpty && isEmail(seg)) {
        detectedEmail = seg;
        emailIndex = i;
      } else if (detectedTwoFactor.isEmpty && isTwoFactorKey(seg)) {
        detectedTwoFactor = seg.replaceAll(' ', '').toUpperCase();
      } else {
        unassigned[i] = seg;
      }
    }

    // Filter out user-agent segments (e.g. Mozilla/5.0...)
    unassigned.removeWhere((_, val) => val.toLowerCase().startsWith('mozilla/'));

    // If segment immediately after email exists in unassigned, it is the email password
    if (emailIndex != -1 && unassigned.containsKey(emailIndex + 1)) {
      detectedEmailPass = unassigned.remove(emailIndex + 1)!;
    }

    // If username is still empty (e.g. segment 0 was a cookie), try extracting from cookie first
    if (detectedUsername.isEmpty && detectedCookie.isNotEmpty) {
      detectedUsername = extractUidFromCookie(detectedCookie) ?? '';
    }

    // Assign remaining unassigned segments in order:
    final remainingIndices = unassigned.keys.toList()..sort();
    
    // If username is still empty, take the first unassigned item
    if (detectedUsername.isEmpty && remainingIndices.isNotEmpty) {
      detectedUsername = unassigned[remainingIndices.removeAt(0)]!;
    }

    if (remainingIndices.isNotEmpty) {
      detectedPassword = unassigned[remainingIndices.removeAt(0)]!;
    }

    if (remainingIndices.isNotEmpty && detectedEmailPass.isEmpty) {
      detectedEmailPass = unassigned[remainingIndices.removeAt(0)]!;
    }

    return ParsedAccount(
      username: detectedUsername,
      password: detectedPassword,
      twoFactorKey: detectedTwoFactor,
      cookie: detectedCookie,
      email: detectedEmail,
      emailPassword: detectedEmailPass,
      rawLine: clean,
    );
  }

  /// Parses multiple lines (e.g. from note.2fa.live content)
  static List<ParsedAccount> parseMultipleLines(String text) {
    final lines = text.split('\n');
    final result = <ParsedAccount>[];

    for (final raw in lines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      // Skip comments or headers if any
      if (trimmed.startsWith('#') || trimmed.startsWith('//')) continue;

      final parsed = parseLine(trimmed);
      // Require at least a username or a cookie or 2fa to be a valid account
      if (parsed.username.isNotEmpty || parsed.cookie.isNotEmpty || parsed.twoFactorKey.isNotEmpty) {
        result.add(parsed);
      }
    }

    return result;
  }
}
