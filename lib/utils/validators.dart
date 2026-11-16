class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập email';
    }
    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegExp.hasMatch(value.trim())) {
      return 'Email không đúng định dạng';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu';
    }
    if (value.length < 6) {
      return 'Mật khẩu phải chứa ít nhất 6 ký tự';
    }
    return null;
  }

  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập tài khoản Instagram';
    }
    final clean = value.trim();
    if (clean.contains(' ')) {
      return 'Tài khoản không được chứa dấu cách';
    }
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập $fieldName';
    }
    return null;
  }

  /// Normalizes the Instagram username to start with '@' if not already present.
  static String normalizeInstagramUsername(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    return clean.startsWith('@') ? clean : '@$clean';
  }

  /// Formats Facebook input into a direct profile link, e.g. https://www.facebook.com/profile.php?id=61585055667699#
  static String formatFacebookProfileUrl(String input) {
    String clean = input.trim();
    if (clean.isEmpty) return '';

    // Remove leading @ if present
    if (clean.startsWith('@')) {
      clean = clean.substring(1).trim();
    }

    // Check if contains profile.php?id=(\d+)
    final idParamMatch = RegExp(r'profile\.php\?id=(\d+)').firstMatch(clean);
    if (idParamMatch != null) {
      final uid = idParamMatch.group(1);
      return 'https://www.facebook.com/profile.php?id=$uid#';
    }

    // Check if input is pure digits (Facebook UID)
    if (RegExp(r'^\d+$').hasMatch(clean)) {
      return 'https://www.facebook.com/profile.php?id=$clean#';
    }

    // Check if facebook.com/(\d+)
    final fbSlashDigitsMatch = RegExp(r'facebook\.com\/(\d+)').firstMatch(clean);
    if (fbSlashDigitsMatch != null) {
      final uid = fbSlashDigitsMatch.group(1);
      return 'https://www.facebook.com/profile.php?id=$uid#';
    }

    // If it's already a full URL
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean.endsWith('#') ? clean : '$clean#';
    }

    // Otherwise, treat as vanity username or fallback
    return 'https://www.facebook.com/$clean#';
  }

  /// Formats the target display in Telegram messages (HTML).
  /// For Facebook, returns a clickable link e.g. <a href="https://www.facebook.com/profile.php?id=61585055667699#">https://www.facebook.com/profile.php?id=61585055667699#</a>
  /// For Instagram, returns <code>$normalizedUsername</code>
  static String formatTelegramTargetDisplay({
    required String accountType,
    required String username,
  }) {
    if (accountType.toLowerCase() == 'facebook') {
      final url = formatFacebookProfileUrl(username);
      return '<a href="$url">$url</a>';
    } else {
      final igUser = normalizeInstagramUsername(username);
      return '<code>$igUser</code>';
    }
  }
}
