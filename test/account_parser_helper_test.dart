import 'package:flutter_test/flutter_test.dart';
import 'package:igcheck/services/meta_checker_service.dart';
import 'package:igcheck/utils/account_parser_helper.dart';

void main() {
  group('AccountParserHelper tests', () {
    test('test checkMetaVerifiedStatus with user cookie', () async {
      const cookie = 'c_user=61593576842930;xs=35:q6ltiJALvLGokw:2:1787432505:-1:-1;fr=0PqP0Ui1GX4gml2ED.AWe1OiQpUHkiePk7RhMWfFTEVRf-MoeXwJha03fdzAndxm';
      final res = await MetaCheckerService.checkMetaVerifiedStatus(cookie: cookie);
      expect(res.statusText, isNotEmpty);
    });

    test('extracts UID|PASS|COOKIE|2FA correctly (cookie before 2FA)', () {
      const line = '1000888999|pass999|c_user=1000888999; xs=some_token;|CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '1000888999');
      expect(acc.password, 'pass999');
      expect(acc.twoFactorKey, 'CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G');
      expect(acc.cookie, 'c_user=1000888999; xs=some_token;');
      expect(acc.hasCookie, isTrue);
      expect(acc.hasTwoFactor, isTrue);
    });

    test('handles standalone cookie string with c_user', () {
      const line = 'datr=xyz; sb=abc; c_user=1000999888; xs=securetoken;';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '1000999888');
      expect(acc.cookie, line);
      expect(acc.hasCookie, isTrue);
      expect(acc.password, isEmpty);
      expect(acc.twoFactorKey, isEmpty);
    });

    test('handles COOKIE|2FA format', () {
      const line = 'c_user=1000777666; xs=tok123;|CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '1000777666');
      expect(acc.cookie, 'c_user=1000777666; xs=tok123;');
      expect(acc.twoFactorKey, 'CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G');
    });

    test('extractCookieOnly extracts cookie from full line', () {
      const line = '100012345678|myPassword123|JBSWY3DPEHPK3PXP|c_user=100012345678; xs=abc123xyz;';
      final cookie = AccountParserHelper.extractCookieOnly(line);

      expect(cookie, 'c_user=100012345678; xs=abc123xyz;');
    });

    test('parseMultipleLines ignores blank lines and extracts all accounts', () {
      const multi = '''
1000111|pass1|JBSWY3DPEHPK3PXP|c_user=1000111; xs=tok1;

1000222|pass2|CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G
c_user=1000333; xs=tok3;
''';
      final list = AccountParserHelper.parseMultipleLines(multi);

      expect(list.length, 3);
      expect(list[0].username, '1000111');
      expect(list[0].hasCookie, isTrue);
      expect(list[1].username, '1000222');
      expect(list[1].hasCookie, isFalse);
      expect(list[2].username, '1000333');
      expect(list[2].hasCookie, isTrue);
    });

    test('extracts UID|PASS|2FA|COOKIE|MAIL|PASSMAIL correctly', () {
      const line = '1000555666|fbPass99|JBSWY3DPEHPK3PXP|c_user=1000555666; xs=tok;|user@hotmail.com|mailPass88';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '1000555666');
      expect(acc.password, 'fbPass99');
      expect(acc.twoFactorKey, 'JBSWY3DPEHPK3PXP');
      expect(acc.cookie, 'c_user=1000555666; xs=tok;');
      expect(acc.email, 'user@hotmail.com');
      expect(acc.emailPassword, 'mailPass88');
      expect(acc.hasEmail, isTrue);
    });

    test('extracts UID|PASS|2FA|MAIL|PASSMAIL correctly', () {
      const line = '1000777888|pass123|CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G|clone@gmail.com|secretMail123';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '1000777888');
      expect(acc.password, 'pass123');
      expect(acc.twoFactorKey, 'CY72QV2PJOUWPPJSAZ5Z4DQCGX5PYN7G');
      expect(acc.email, 'clone@gmail.com');
      expect(acc.emailPassword, 'secretMail123');
      expect(acc.hasEmail, isTrue);
    });

    test('extracts Instagram USER|PASS|2FA|COOKIE correctly', () {
      const line = 'andratrevino177172|%gG^c6fua|FQHNI4WXJT42HG23|csrftoken=BUGBdsoZMNWmIIxxvR01eL9s5YxRz0XO;datr=PhDFavSsjqeO1mWxf3N3zUnb;ig_did=099BBAD9-010C-42EC-9AB7-E8237725687A;mid=asUQPgALAAEKYAZzw9peFfKfjPPA;rur="SNB5418809857917541822835653:01ff2927d4679a082ca7b29a004b006f32b2169461ba9f964f14e9d41470024ac272e752";ds_user_id=18809857917;sessionid=18809857917%3AJlvKAr1bti50NV%3A28%3AAYnxZcZj5oLNGEyro0Z2W4S1eGqubxqkew2gzhBH5w;';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, 'andratrevino177172');
      expect(acc.password, '%gG^c6fua');
      expect(acc.twoFactorKey, 'FQHNI4WXJT42HG23');
      expect(acc.cookie.contains('sessionid=18809857917'), isTrue);
      expect(acc.cookie.contains('csrftoken=BUGBdsoZMNWmIIxxvR01eL9s5YxRz0XO'), isTrue);
      expect(acc.hasCookie, isTrue);
      expect(acc.hasTwoFactor, isTrue);
      expect(acc.hasPassword, isTrue);
    });

    test('extracts Instagram USER|PASS|2FA without cookie', () {
      const line = 'johnapfohl477852|vu!K^b3KOR|2NMG4JYYGDAMQJIY';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, 'johnapfohl477852');
      expect(acc.password, 'vu!K^b3KOR');
      expect(acc.twoFactorKey, '2NMG4JYYGDAMQJIY');
      expect(acc.hasCookie, isFalse);
      expect(acc.hasTwoFactor, isTrue);
      expect(acc.hasPassword, isTrue);
    });

    test('extracts standalone Instagram cookie with ds_user_id', () {
      const line = 'csrftoken=xyz; ds_user_id=18809857917; sessionid=18809857917%3Aabc;';
      final acc = AccountParserHelper.parseLine(line);

      expect(acc.username, '18809857917');
      expect(acc.cookie, line);
      expect(acc.hasCookie, isTrue);
    });
  });
}
