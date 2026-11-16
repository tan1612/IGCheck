class DocumentProfileName {
  final String fullName;
  final String givenName;
  final String middleName;
  final String familyName;

  const DocumentProfileName({
    required this.fullName,
    required this.givenName,
    required this.middleName,
    required this.familyName,
  });

  factory DocumentProfileName.fromJson(Map<String, dynamic> json) {
    String field(String key) => (json[key] as String? ?? '').trim();
    final name = DocumentProfileName(
      fullName: field('fullName'),
      givenName: field('givenName'),
      middleName: field('middleName'),
      familyName: field('familyName'),
    );
    final confidence = json['confidence'];
    if (confidence is! num || confidence < 0.9 || !name.isValid) {
      throw const FormatException('Không đọc rõ họ tên trên giấy tờ.');
    }
    return name;
  }

  bool get isValid {
    bool validPart(String value, {bool optional = false}) =>
        (optional || value.isNotEmpty) &&
        value.length <= 150 &&
        !RegExp(r'[\d\r\n:{}\[\]]').hasMatch(value) &&
        !value.toUpperCase().contains('LỖI') &&
        !value.toUpperCase().contains('KHÔNG ĐỌC ĐƯỢC');
    if (!validPart(fullName) ||
        !validPart(givenName) ||
        !validPart(familyName) ||
        !validPart(middleName, optional: true)) {
      return false;
    }
    List<String> words(String value) =>
        value.toLowerCase().split(RegExp(r'\s+'))..sort();
    return words(fullName).join(' ') ==
        words(
          '$familyName ${middleName.isEmpty ? '' : '$middleName '}$givenName',
        ).join(' ').trim();
  }

  Map<String, String> toJson() => {
    'fullName': fullName,
    'givenName': givenName,
    'middleName': middleName,
    'familyName': familyName,
  };
}
