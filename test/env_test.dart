import 'package:hossouko_merchant/core/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('exposes an API base and sane timeouts', () {
      expect(Env.apiBase, isNotEmpty);
      expect(Env.apiBase, isNot(endsWith('/')),
          reason: 'paths are joined assuming no trailing slash');
      expect(Env.requestTimeout.inSeconds, greaterThan(0));
      expect(Env.connectTimeout, lessThan(Env.requestTimeout));
    });

    test('assertHttpsInRelease is a no-op in a debug or test build', () {
      // `flutter test` runs in JIT, so isRelease is false and the guard must
      // not fire even though the default apiBase is http loopback.
      expect(Env.isRelease, isFalse);
      expect(Env.assertHttpsInRelease, returnsNormally);
    });
  });
}
