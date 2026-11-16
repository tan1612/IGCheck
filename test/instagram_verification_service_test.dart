import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:igcheck/services/instagram_verification_service.dart';

void main() {
  group('InstagramVerificationService Tests', () {
    test('Facebook requires both session cookie fields', () async {
      for (final cookie in ['c_user=123', 'xs=session']) {
        final result = await InstagramVerificationService.submitVerification(
          cookie: cookie,
          platform: 'facebook',
          documentImages: [
            Uint8List.fromList([1, 2, 3]),
          ],
        );
        expect(result.status, InstagramVerifyStatus.sessionExpired);
      }
    });

    test(
      'Facebook cannot fall through to the Instagram upload endpoint',
      () async {
        final result = await InstagramVerificationService.submitVerification(
          cookie: 'c_user=123; xs=session',
          platform: 'facebook',
          documentImages: [
            Uint8List.fromList([1, 2, 3]),
          ],
        );
        expect(result.status, InstagramVerifyStatus.error);
        expect(result.title, contains('trình duyệt'));
      },
    );

    test(
      'parseCookieTokens correctly extracts all Instagram cookie attributes',
      () {
        const sampleCookie =
            'datr=kBfXaiqJYTA; ig_did=5C7E0950; mid=atcXkA; csrftoken=EFxeN3hy18bnd; ds_user_id=17903831692; sessionid=17903831692%3AWGtDwl7; rur="NHA"';

        final tokens = InstagramVerificationService.parseCookieTokens(
          sampleCookie,
        );

        expect(tokens['sessionid'], equals('17903831692%3AWGtDwl7'));
        expect(tokens['csrftoken'], equals('EFxeN3hy18bnd'));
        expect(tokens['ds_user_id'], equals('17903831692'));
        expect(tokens['mid'], equals('atcXkA'));
        expect(tokens['ig_did'], equals('5C7E0950'));
        expect(tokens['datr'], equals('kBfXaiqJYTA'));
      },
    );

    test('submitVerification returns error when cookie is empty', () async {
      final result = await InstagramVerificationService.submitVerification(
        cookie: '',
        documentImages: [
          Uint8List.fromList([1, 2, 3]),
        ],
      );

      expect(result.status, equals(InstagramVerifyStatus.error));
      expect(result.title, contains('Thiếu Cookie'));
    });

    test(
      'submitVerification returns error when no images are provided',
      () async {
        final result = await InstagramVerificationService.submitVerification(
          cookie: 'sessionid=12345; ds_user_id=123',
          documentImages: [],
        );

        expect(result.status, equals(InstagramVerifyStatus.error));
        expect(result.title, contains('Thiếu ảnh giấy tờ'));
      },
    );

    test(
      'submitVerification returns sessionExpired when sessionid is missing',
      () async {
        final result = await InstagramVerificationService.submitVerification(
          cookie: 'csrftoken=abcdef; ds_user_id=123',
          documentImages: [
            Uint8List.fromList([1, 2, 3]),
          ],
        );

        expect(result.status, equals(InstagramVerifyStatus.sessionExpired));
        expect(result.title, contains('Cookie không hợp lệ'));
      },
    );
  });
}
