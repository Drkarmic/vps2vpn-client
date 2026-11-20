import 'dart:async';

import 'package:fl_clash/vps2vpn/simple_mode.dart';

/// The suite tests FlClash's own pages, so it runs with vps2vpn's simple
/// mode out of the way; tests of simple mode turn it back on for themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  vps2vpnUpstreamUi = true;
  await testMain();
}
