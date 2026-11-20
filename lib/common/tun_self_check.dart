// vps2vpn: TUN self-check. Some Windows machines turn TUN on without an
// adapter ever coming up (FlClash #3020: default `mips` stack, no adapter, no
// routes, the UI still showing TUN on). A few seconds after TUN is asked for,
// this asks the Core whether the listener is up and, if not, retries once on
// gVisor. See core/lifecycle.go handleTunStatus for the Core side.

import 'dart:async';

import 'package:fl_clash/enum/enum.dart';

/// What `tun.status` answers.
class TunStatus {
  /// The Core's listeners run (`listener.start` without a later stop).
  final bool running;

  /// The applied config asks for the TUN.
  final bool requested;

  /// mihomo created the adapter and started the stack.
  final bool up;
  final String stack;

  const TunStatus({
    required this.running,
    required this.requested,
    required this.up,
    this.stack = '',
  });

  factory TunStatus.fromJson(Map<String, Object?> json) => TunStatus(
    running: json['running'] == true,
    requested: json['requested'] == true,
    up: json['up'] == true,
    stack: json['stack'] is String ? json['stack'] as String : '',
  );
}

enum TunHealth { up, down, unknown }

/// Only a running Core that was asked for the TUN can say it failed; a Core
/// out of reach or one too old for `tun.status` gives `null`, never a retry.
TunHealth tunHealthOf(TunStatus? status) {
  if (status == null || !status.running || !status.requested) {
    return TunHealth.unknown;
  }
  return status.up ? TunHealth.up : TunHealth.down;
}

/// gVisor is a userspace stack like mips; mihomo's docs say system and mixed
/// cannot work while the firewall is on
/// (https://wiki.metacubex.one/config/inbound/tun/, `stack`). It is also the
/// end of the line, so an automatic switch can never cycle between stacks.
TunStack? fallbackTunStack(TunStack stack) =>
    stack == TunStack.gvisor ? null : TunStack.gvisor;

enum TunCheckStep {
  /// Up, or nothing to judge.
  keep,

  /// Down on a stack that has a fallback not yet tried.
  retry,

  /// Down with nothing left to try: tell the user, change nothing.
  giveUp,
}

typedef TunCheckDecision = ({TunCheckStep step, TunStack? stack});

TunCheckDecision decideTunCheck({
  required TunHealth health,
  required TunStack stack,
  required bool retried,
}) {
  if (health != TunHealth.down) {
    return (step: TunCheckStep.keep, stack: null);
  }
  final fallback = fallbackTunStack(stack);
  if (fallback == null || retried) {
    return (step: TunCheckStep.giveUp, stack: null);
  }
  return (step: TunCheckStep.retry, stack: fallback);
}

/// Runs [decideTunCheck] [delay] after [schedule]: at most one retry and one
/// give-up notice until [reset], which the TUN being switched off calls.
class TunSelfCheck {
  final Future<TunStatus?> Function() readStatus;
  final TunStack Function() currentStack;
  final void Function(TunStack stack) switchStack;
  final void Function(TunCheckStep step, TunStack from, TunStack? to) notify;
  final Duration delay;

  TunSelfCheck({
    required this.readStatus,
    required this.currentStack,
    required this.switchStack,
    required this.notify,
    this.delay = const Duration(seconds: 5),
  });

  Timer? _timer;
  var _retried = false;
  var _gaveUp = false;

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(run()));
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _retried = false;
    _gaveUp = false;
  }

  void dispose() => _timer?.cancel();

  Future<void> run() async {
    _timer = null;
    final TunStatus? status;
    try {
      status = await readStatus();
    } catch (_) {
      return;
    }
    final stack = currentStack();
    final decision = decideTunCheck(
      health: tunHealthOf(status),
      stack: stack,
      retried: _retried,
    );
    switch (decision.step) {
      case TunCheckStep.keep:
        return;
      case TunCheckStep.retry:
        _retried = true;
        switchStack(decision.stack!);
        notify(TunCheckStep.retry, stack, decision.stack);
        schedule();
      case TunCheckStep.giveUp:
        if (_gaveUp) return;
        _gaveUp = true;
        notify(TunCheckStep.giveUp, stack, null);
    }
  }
}
