import 'package:fl_clash/core/controller.dart';
import 'package:riverpod/riverpod.dart' show Notifier, NotifierProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/core.g.dart';

@Riverpod(keepAlive: true)
CoreController coreHandler(Ref ref) => coreController;

/// Counts the Core's full network resets (CoreAction.resetNetwork), so a
/// check that runs on a timer can look again at once.
final networkResetsProvider = NotifierProvider<NetworkResets, int>(
  NetworkResets.new,
);

class NetworkResets extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
