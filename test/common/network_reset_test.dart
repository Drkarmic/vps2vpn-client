import 'package:fl_clash/common/network_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int resets;
  late NetworkResetTrigger trigger;

  setUp(() {
    resets = 0;
    trigger = NetworkResetTrigger(onReset: () => resets++);
  });

  tearDown(() => trigger.dispose());

  bool report(String defaultInterface, {bool resumed = false}) {
    return trigger.report(resumed: resumed, defaultInterface: defaultInterface);
  }

  testWidgets('the first report only learns the default interface', (
    tester,
  ) async {
    expect(report('wifi'), isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 0);
  });

  testWidgets('churn on the same default interface does not reset', (
    tester,
  ) async {
    report('wifi');
    expect(report('wifi'), isFalse);
    expect(report('wifi'), isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 0);
  });

  testWidgets('a move of the default interface resets once it settles', (
    tester,
  ) async {
    report('wifi');
    expect(report('ethernet'), isTrue);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(resets, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(resets, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 1);
  });

  testWidgets('losing the network waits for the one that comes back', (
    tester,
  ) async {
    report('wifi');
    expect(report(''), isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 0);
    expect(report('wifi'), isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(resets, 1);
  });

  testWidgets('a wake resets even on the same network', (tester) async {
    expect(report('wifi', resumed: true), isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(resets, 1);
  });

  testWidgets('a wake and the reconnect after it reset once', (tester) async {
    report('wifi');
    report('wifi', resumed: true);
    await tester.pump(const Duration(seconds: 1));
    report('');
    await tester.pump(const Duration(seconds: 1));
    report('wifi');
    await tester.pump(const Duration(seconds: 1));
    expect(resets, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(resets, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 1);
  });

  testWidgets('a burst that never goes quiet resets at the cap', (
    tester,
  ) async {
    report('a');
    for (var i = 0; i < 9; i++) {
      report(i.isEven ? 'b' : 'a');
      await tester.pump(const Duration(seconds: 1));
    }
    expect(resets, 1);
    expect(trigger.isPending, isTrue);
    trigger.dispose();
  });

  testWidgets('dispose drops a pending reset', (tester) async {
    report('wifi', resumed: true);
    trigger.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(resets, 0);
  });

  testWidgets('a failing reset does not escape', (tester) async {
    final failing = NetworkResetTrigger(
      onReset: () async => throw StateError('core gone'),
    );
    addTearDown(failing.dispose);
    failing.report(resumed: true, defaultInterface: '');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
