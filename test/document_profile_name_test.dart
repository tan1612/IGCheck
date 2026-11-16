import 'package:flutter_test/flutter_test.dart';
import 'package:igcheck/models/document_profile_name.dart';

void main() {
  test('accepts a clear full name whose components match the document', () {
    final name = DocumentProfileName.fromJson({
      'fullName': 'Nguyễn Văn An',
      'givenName': 'An',
      'middleName': 'Văn',
      'familyName': 'Nguyễn',
      'confidence': 0.98,
    });
    expect(name.isValid, isTrue);
    expect(name.toJson()['givenName'], 'An');
  });
  test('rejects uncertain OCR and invented name components', () {
    expect(
      () => DocumentProfileName.fromJson({
        'fullName': 'Nguyễn Văn An',
        'givenName': 'An',
        'middleName': 'Văn',
        'familyName': 'Nguyễn',
        'confidence': 0.5,
      }),
      throwsFormatException,
    );
    expect(
      () => DocumentProfileName.fromJson({
        'fullName': 'Nguyễn Văn An',
        'givenName': 'Bình',
        'middleName': 'Văn',
        'familyName': 'Nguyễn',
        'confidence': 0.99,
      }),
      throwsFormatException,
    );
  });
  test('accepts a name with no middle name and rejects OCR error text', () {
    expect(
      const DocumentProfileName(
        fullName: 'Lê An',
        givenName: 'An',
        middleName: '',
        familyName: 'Lê',
      ).isValid,
      isTrue,
    );
    expect(
      const DocumentProfileName(
        fullName: 'LỖI NETWORK',
        givenName: 'NETWORK',
        middleName: '',
        familyName: 'LỖI',
      ).isValid,
      isFalse,
    );
  });
}
