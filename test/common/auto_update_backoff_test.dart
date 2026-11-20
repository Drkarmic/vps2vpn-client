import 'package:fl_clash/common/auto_update_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doubles the wait after each failure up to the longest', () {
    expect(
      [
        for (var failures = 1; failures <= 7; failures++) failures,
      ].map(AutoUpdateBackoff.delay),
      const [
        Duration(minutes: 20),
        Duration(minutes: 40),
        Duration(minutes: 80),
        Duration(minutes: 160),
        Duration(minutes: 320),
        Duration(hours: 6),
        Duration(hours: 6),
      ],
    );
    expect(AutoUpdateBackoff.delay(64), AutoUpdateBackoff.longestDelay);
  });

  test('holds a failed key back until its wait is over', () {
    var now = DateTime(2026, 11, 20);
    final backoff = AutoUpdateBackoff(now: () => now);

    expect(backoff.isDue(1), isTrue);
    backoff.fail(1);
    expect(backoff.isDue(1), isFalse);
    expect(backoff.isDue(2), isTrue);

    now = now.add(const Duration(minutes: 19));
    expect(backoff.isDue(1), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(backoff.isDue(1), isTrue);
  });

  test('asks for one notice per run of failures', () {
    final backoff = AutoUpdateBackoff();

    expect(
      [for (var i = 0; i < 5; i++) backoff.fail(1)],
      [false, true, false, false, false],
    );

    backoff.succeed(1);
    expect(backoff.failures(1), 0);
    expect(backoff.isDue(1), isTrue);
    expect([backoff.fail(1), backoff.fail(1)], [false, true]);
  });
}
