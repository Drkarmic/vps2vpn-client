import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/vps2vpn/mine.dart';
import 'package:fl_clash/vps2vpn/panel.dart';
import 'package:fl_clash/vps2vpn/subscription_notice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../helpers/host_scaffold.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _info = SubscriptionInfo(
  total: 100,
  announce: 'Account paused: renew to continue',
  webPageUrl: 'https://panel.example/me',
  supportUrl: 'tg://resolve?domain=help',
);

const _profile = Profile(
  id: 1,
  type: ProfileType.url,
  label: 'Line',
  url: 'https://panel.example/s/token',
  autoUpdateDuration: Duration(hours: 1),
  subscriptionInfo: _info,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  globalState.container = container;
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1200, 1800));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(locale: const Locale('en'), child: child),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('the extras show the announcement and both links', (
    tester,
  ) async {
    await _pump(
      tester,
      const HostScaffold(body: VpsSubscriptionExtras(info: _info)),
    );

    expect(find.text('Account paused: renew to continue'), findsOneWidget);
    expect(find.text('My page'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
  });

  testWidgets('a link asks before it leaves the app', (tester) async {
    await _pump(
      tester,
      const HostScaffold(body: VpsSubscriptionExtras(info: _info)),
    );

    await tester.tap(find.text('Contact support'));
    await tester.pumpAndSettle();

    expect(find.text('External link'), findsOneWidget);
    expect(find.text('tg://resolve?domain=help'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('External link'), findsNothing);
  });

  testWidgets('a subscription without extras shows nothing', (tester) async {
    await _pump(
      tester,
      const HostScaffold(
        body: VpsSubscriptionExtras(info: SubscriptionInfo(total: 100)),
      ),
    );

    expect(hasSubscriptionExtras(const SubscriptionInfo(total: 1)), isFalse);
    expect(hasSubscriptionExtras(null), isFalse);
    expect(find.byType(Wrap), findsNothing);
    expect(find.text('My page'), findsNothing);
  });

  testWidgets('the overview notice follows the announcement in use', (
    tester,
  ) async {
    await _pump(
      tester,
      const HostScaffold(body: VpsSubscriptionNotice()),
      overrides: [currentProfileProvider.overrideWithValue(_profile)],
    );
    expect(find.text('Account paused: renew to continue'), findsOneWidget);
  });

  testWidgets('the overview notice hides links without an announcement', (
    tester,
  ) async {
    await _pump(
      tester,
      const HostScaffold(body: VpsSubscriptionNotice()),
      overrides: [
        currentProfileProvider.overrideWithValue(
          _profile.copyWith(subscriptionInfo: _info.copyWith(announce: null)),
        ),
      ],
    );
    expect(find.text('My page'), findsNothing);
  });

  testWidgets('the Me page card shows the extras of a subscription', (
    tester,
  ) async {
    await _pump(
      tester,
      const VpsMePage(),
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([_profile])),
        vpsMemberProvider.overrideWith((ref) async => null),
        localIpProvider.overrideWithValue(null),
      ],
    );

    expect(find.text('Account paused: renew to continue'), findsOneWidget);
    expect(find.text('My page'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
  });
}
