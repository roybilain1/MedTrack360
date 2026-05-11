import 'package:flutter_test/flutter_test.dart';
import 'package:medtrack_pos/services/sync_manager.dart';

void main() {
  group('SyncBackoffPolicy', () {
    test('grows exponentially from base delay', () {
      const policy = SyncBackoffPolicy(
        baseMs: 1000,
        maxExponent: 6,
        maxJitterMs: 500,
      );

      expect(policy.nextDelay(0), const Duration(milliseconds: 1000));
      expect(policy.nextDelay(1), const Duration(milliseconds: 2000));
      expect(policy.nextDelay(2), const Duration(milliseconds: 4000));
    });

    test('caps exponent to avoid unbounded delays', () {
      const policy = SyncBackoffPolicy(
        baseMs: 1000,
        maxExponent: 3,
        maxJitterMs: 500,
      );

      expect(policy.nextDelay(3), const Duration(milliseconds: 8000));
      expect(policy.nextDelay(10), const Duration(milliseconds: 8000));
    });

    test('bounds jitter between zero and max', () {
      const policy = SyncBackoffPolicy(
        baseMs: 1000,
        maxExponent: 1,
        maxJitterMs: 500,
      );

      expect(
        policy.nextDelay(1, jitterMs: -50),
        const Duration(milliseconds: 2000),
      );
      expect(
        policy.nextDelay(1, jitterMs: 999),
        const Duration(milliseconds: 2500),
      );
      expect(
        policy.nextDelay(1, jitterMs: 123),
        const Duration(milliseconds: 2123),
      );
    });
  });
}
