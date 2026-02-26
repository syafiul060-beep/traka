import 'package:flutter_test/flutter_test.dart';

import 'package:traka/utils/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('log does not throw with message only', () {
      expect(() => log('test message'), returnsNormally);
    });

    test('log does not throw with error', () {
      expect(
        () => log('test', Exception('error')),
        returnsNormally,
      );
    });

    test('log does not throw with error and stackTrace', () {
      expect(
        () => log('test', Exception('error'), StackTrace.current),
        returnsNormally,
      );
    });
  });
}
