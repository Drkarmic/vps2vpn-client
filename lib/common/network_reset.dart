import 'dart:async';

/// Decides when the desktop Core needs a full network reset: after a wake
/// from sleep, and when the default route moves to another interface, but
/// not for the address and route churn of a network it stays on. Connections
/// and QUIC sessions opened over the old path otherwise hang until they time
/// out.
///
/// A wake and the reconnect that follows it arrive as a burst of reports, so
/// the reset waits for [quiet] without a new report, and at most [maxDelay]
/// after the first one that asked for it.
class NetworkResetTrigger {
  NetworkResetTrigger({
    required this.onReset,
    this.quiet = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 8),
  });

  final FutureOr<void> Function() onReset;
  final Duration quiet;
  final Duration maxDelay;

  String? _defaultInterface;
  Timer? _quietTimer;
  Timer? _maxTimer;

  bool get isPending => _quietTimer != null;

  /// Takes one network report and answers whether it asks for a reset. The
  /// first report only sets what the default interface is; one without a
  /// default interface leaves nothing to reset onto, so the reset waits for
  /// the network that comes back.
  bool report({required bool resumed, required String defaultInterface}) {
    final previous = _defaultInterface;
    _defaultInterface = defaultInterface;
    final moved =
        previous != null &&
        defaultInterface.isNotEmpty &&
        defaultInterface != previous;
    final asks = resumed || moved;
    // Any report while one is pending belongs to the same burst.
    if (asks || isPending) {
      _quietTimer?.cancel();
      _quietTimer = Timer(quiet, _fire);
      _maxTimer ??= Timer(maxDelay, _fire);
    }
    return asks;
  }

  void _fire() {
    _cancel();
    unawaited(Future.sync(onReset).catchError((_) {}));
  }

  void _cancel() {
    _quietTimer?.cancel();
    _quietTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
  }

  void dispose() => _cancel();
}
