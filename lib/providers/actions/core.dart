part of '../action.dart';

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  static final Object _restartWorkerZoneKey = Object();

  int _requestedRestartRevision = 0;
  bool _needsLifecycleRestart = false;
  bool _restartingLifecycle = false;
  Future<bool>? _restartOperation;
  Future<void>? _startOperation;

  @override
  void build() {}

  Future<void> initCore() async {
    final isInit = await _core.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      await _core.init(version);
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      await ref.read(providersProvider.notifier).syncProviders();
    }
  }

  Future<void> startCore() {
    final activeStart = _startOperation;
    if (activeStart != null) {
      return activeStart;
    }
    final operation = _runStartCore();
    _startOperation = operation;
    return operation;
  }

  Future<void> _runStartCore() async {
    try {
      final activeRestart = _restartOperation;
      if (activeRestart != null) {
        try {
          await activeRestart;
        } catch (_) {}
        if (ref.read(coreStatusProvider) == CoreStatus.connected) {
          return;
        }
      }
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      try {
        final result = await startLifecycle();
        await _applyLifecycleResult(result);
      } catch (error) {
        _markStopped(error);
        dialogs.showBanner(
          ref.read(coreStopReasonProvider) ?? '',
          level: BannerLevel.error,
        );
      }
    } finally {
      _startOperation = null;
    }
  }

  void _markStopped(Object error) {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    final reason = userFacingErrorMessage(error, currentAppLocalizations);
    ref.read(coreStopReasonProvider.notifier).value = reason.isEmpty
        ? null
        : reason;
  }

  @protected
  Future<CoreLifecycleResult> startLifecycle() {
    return _core.start();
  }

  @protected
  Future<CoreLifecycleResult> restartLifecycle() {
    return _core.restart();
  }

  // Nothing in lib/ calls CoreController.stop(); only close() (app exit)
  // supersedes a start/restart. statusFirst lets onCrash catch a crash
  // during initCore itself (it early-returns unless status is connected).
  Future<bool> _applyLifecycleResult(
    CoreLifecycleResult result, {
    bool statusFirst = false,
  }) async {
    if (result.outcome == CoreLifecycleOutcome.superseded) {
      return false;
    }
    if (statusFirst) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await initCore();
    } else {
      await initCore();
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    }
    if (rsFeature && ref.read(patchClashConfigProvider).mitm.enable) {
      unawaited(ref.read(mitmTrustStateProvider.notifier).refresh());
    }
    return true;
  }

  Future<void> closeConnection(String id) async {
    await _core.closeConnection(id);
  }

  Future<void> closeConnections() async {
    await _core.closeConnections();
  }

  Future<void> reportNetworkChange() async {
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    try {
      await _core.reportNetworkChange();
    } catch (error) {
      commonPrint.log(
        'reportNetworkChange error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<void> forceGc() async {
    await _core.forceGc();
  }

  Future<void> crash() async {
    await _core.crash();
  }

  Future<bool> restartCore() {
    _requestedRestartRevision++;
    if (!_restartingLifecycle) {
      _needsLifecycleRestart = true;
    }
    final activeOperation = _restartOperation;
    if (activeOperation != null) {
      // Re-entrant call (e.g. TUN authorization inside setup triggering a core
      // restart while _runRestartWorker is awaiting setup): avoid self-deadlock
      // by letting the active worker loop run the next lifecycle restart.
      if (identical(Zone.current[_restartWorkerZoneKey], this)) {
        return Future.value(true);
      }
      return activeOperation;
    }

    final operation = _runRestartWorker();
    _restartOperation = operation;
    return operation;
  }

  Future<bool> _runRestartWorker() {
    return runZoned(() async {
      try {
        var appliedRevision = 0;
        var applied = true;
        while (appliedRevision < _requestedRestartRevision ||
            _needsLifecycleRestart) {
          final needLifecycle =
              _needsLifecycleRestart ||
              ref.read(coreStatusProvider) != CoreStatus.connected;
          if (needLifecycle) {
            _needsLifecycleRestart = false;
            _restartingLifecycle = true;
            ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
            final CoreLifecycleResult result;
            try {
              result = await restartLifecycle();
            } finally {
              _restartingLifecycle = false;
            }
            if (!await _applyLifecycleResult(result, statusFirst: true)) {
              return false;
            }
            if (_needsLifecycleRestart) {
              continue;
            }
          }

          final revision = _requestedRestartRevision;
          if (ref.read(setupActionProvider.notifier).wantsRunning) {
            applied = await ref
                .read(setupActionProvider.notifier)
                .setRunning(true, initialize: true);
          } else {
            applied = await ref
                .read(setupActionProvider.notifier)
                .applyProfile(force: true);
          }
          appliedRevision = revision;
        }
        return applied;
      } catch (error) {
        _markStopped(error);
        rethrow;
      } finally {
        _needsLifecycleRestart = false;
        _restartingLifecycle = false;
        _restartOperation = null;
      }
    }, zoneValues: {_restartWorkerZoneKey: this});
  }
}
