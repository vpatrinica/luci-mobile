import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

void main() {
  group('RUTOS login token handling', () {
    test('redirected login without token is treated as failure', () {
      expect(
        normalizeLoginToken(
          token: null,
          redirectedToHttps: true,
          wasUsingHttp: true,
        ),
        isNull,
      );
    });

    test('redirected login with token is marked as HTTPS redirect', () {
      expect(
        normalizeLoginToken(
          token: 'abc123',
          redirectedToHttps: true,
          wasUsingHttp: true,
        ),
        'HTTPS_REDIRECT:abc123',
      );
    });
  });
}
