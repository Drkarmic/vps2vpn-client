import 'dart:async';

import 'package:fl_clash/common/tun_self_check.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

const _down = TunStatus(running: true, requested: true, up: false);
const _up = TunStatus(running: true, requested: true, up: true);

void main() {
  group('tunHealthOf', () {
    test('judges only a running Core that was asked for the TUN', () {
      expect(tunHealthOf(_up), TunHealth.up);
      expect(tunHealthOf(_down), TunHealth.down);
      expect(tunHealthOf(null), TunHealth.unknown);
      expect(
        tunHealthOf(
          const TunStatus(running: false, requested: true, up: false),
        ),
        TunHealth.unknown,
      );
      expect(
        tunHealthOf(
          const TunStatus(running: true, requested: false, up: false),
        ),
        TunHealth.unknown,
      );
    });

    test('reads the Core answer, missing fields as false', () {
      final status = TunStatus.fromJson({
        'running': true,
        'requested': true,
        'stack': 'Mips',
      });
      expect(status.up, isFalse);
      expect(status.stack, 'Mips');
      expect(tunHealthOf(status), TunHealth.down);
    });
  });

  group('decideTunCheck', () {
    test('falls back to gVisor from every other stack, once', () {
      for (final stack in [TunStack.mips, TunStack.system, TunStack.mixed]) {
        expect(
          decideTunCheck(health: TunHealth.down, stack: stack, retried: false),
          (step: TunCheckStep.retry, stack: TunStack.gvisor),
        );
        expect(
          decideTunCheck(
            health: TunHealth.down,
            stack: stack,
            retried: true,
          ).step,
          TunCheckStep.giveUp,
        );
      }
    });

    test('never leaves gVisor, so stacks cannot cycle', () {
      expect(fallbackTunStack(TunStack.gvisor), isNull);
      expect(
        decideTunCheck(
          health: TunHealth.down,
          stack: TunStack.gvisor,
          retried: false,
        ).step,
        TunCheckStep.giveUp,
      );
    });

    test('changes nothing when up or unknown', () {
      for (final health in [TunHealth.up, TunHealth.unknown]) {
        expect(
          decideTunCheck(health: health, stack: TunStack.mips, retried: false),
          (step: TunCheckStep.keep, stack: null),
        );
      }
    });
  });

  group('TunSelfCheck', () {
    late List<TunStatus?> answers;
    late TunStack stack;
    late List<(TunCheckStep, TunStack, TunStack?)> notices;
    late TunSelfCheck check;

    setUp(() {
      answers = [];
      stack = TunStack.mips;
      notices = [];
      check = TunSelfCheck(
        readStatus: () async => answers.removeAt(0),
        currentStack: () => stack,
        switchStack: (next) => stack = next,
        notify: (step, from, to) => notices.add((step, from, to)),
        delay: const Duration(days: 1),
      );
    });

    tearDown(() => check.dispose());

    test('retries once on gVisor, then only tells the user', () async {
      answers = [_down, _down, _down];

      await check.run();
      expect(stack, TunStack.gvisor);
      expect(notices, [(TunCheckStep.retry, TunStack.mips, TunStack.gvisor)]);

      await check.run();
      await check.run();
      expect(stack, TunStack.gvisor);
      expect(notices, [
        (TunCheckStep.retry, TunStack.mips, TunStack.gvisor),
        (TunCheckStep.giveUp, TunStack.gvisor, null),
      ]);
    });

    test('keeps the stack that came up', () async {
      answers = [_down, _up];

      await check.run();
      await check.run();

      expect(stack, TunStack.gvisor);
      expect(notices, hasLength(1));
    });

    test('a Core that cannot answer changes nothing', () async {
      final failing = TunSelfCheck(
        readStatus: () async => throw StateError('unknown method'),
        currentStack: () => stack,
        switchStack: (next) => stack = next,
        notify: (step, from, to) => notices.add((step, from, to)),
      );

      await failing.run();

      expect(stack, TunStack.mips);
      expect(notices, isEmpty);
    });

    test('a check under way when the TUN goes off changes nothing', () async {
      final answer = Completer<TunStatus?>();
      final slow = TunSelfCheck(
        readStatus: () => answer.future,
        currentStack: () => stack,
        switchStack: (next) => stack = next,
        notify: (step, from, to) => notices.add((step, from, to)),
      );
      addTearDown(slow.dispose);

      final run = slow.run();
      slow.reset();
      answer.complete(_down);
      await run;

      expect(stack, TunStack.mips);
      expect(notices, isEmpty);
    });

    test('reset gives the next enable its own retry', () async {
      stack = TunStack.system;
      answers = [_down, _down];
      await check.run();
      await check.run();
      expect(notices.last.$1, TunCheckStep.giveUp);

      check.reset();
      stack = TunStack.mixed;
      answers = [_down];
      await check.run();

      expect(notices.last, (
        TunCheckStep.retry,
        TunStack.mixed,
        TunStack.gvisor,
      ));
    });
  });
}
