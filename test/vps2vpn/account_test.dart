import 'package:fl_clash/vps2vpn/account.dart';
import 'package:fl_clash/vps2vpn/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  VpsMemberResult? result,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [vpsMemberProvider.overrideWith((ref) async => result)],
      child: MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _gb = 1024 * 1024 * 1024;

void main() {
  testWidgets('hidden for subscriptions that are not vps2vpn links', (
    tester,
  ) async {
    await _pump(tester, const VpsAccountCard(), null);
    expect(find.byType(Text), findsNothing);
    await _pump(tester, const VpsServerAiCard(), null);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows usage against the quota and the expiry', (tester) async {
    await _pump(
      tester,
      const VpsAccountCard(),
      VpsMemberResult(
        member: VpsMember(
          name: 'Ann',
          enabled: true,
          usedDown: 2 * _gb,
          quotaGb: 10,
          expireAt: DateTime.now().add(const Duration(days: 12, hours: 1)),
        ),
      ),
    );
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('Used 2'), findsOneWidget);
    expect(find.text('Expires in 12 days'), findsOneWidget);
  });

  testWidgets('says why the account is off', (tester) async {
    await _pump(
      tester,
      const VpsAccountCard(),
      const VpsMemberResult(
        member: VpsMember(
          name: 'Ann',
          enabled: false,
          disabledReason: 'devices',
        ),
      ),
    );
    expect(find.text('Paused for a while: too many devices'), findsOneWidget);
    expect(find.textContaining('unlimited'), findsOneWidget);
  });

  testWidgets('a replaced link asks for the new one', (tester) async {
    await _pump(
      tester,
      const VpsAccountCard(),
      const VpsMemberResult(linkChanged: true),
    );
    expect(find.text('Your link was replaced'), findsOneWidget);
  });

  testWidgets('lists what the server sees for each AI site', (tester) async {
    await _pump(
      tester,
      const VpsServerAiCard(),
      const VpsMemberResult(
        member: VpsMember(
          name: 'Ann',
          enabled: true,
          ai: VpsAiStatus(
            summary: 'Claude works from this server',
            place: 'Singapore',
            sites: {'claude': 'ok', 'chatgpt': 'blocked'},
          ),
        ),
      ),
    );
    expect(find.text('Seen from your server'), findsOneWidget);
    expect(find.text('Claude works from this server'), findsOneWidget);
    expect(find.text('Claude · OK'), findsOneWidget);
    expect(find.text('ChatGPT · Blocked'), findsOneWidget);
    expect(find.textContaining('Gemini'), findsNothing);
  });

  testWidgets('offers a newer client from the panel, not an older one', (
    tester,
  ) async {
    VpsMemberResult withClient(String v) => VpsMemberResult(
      member: VpsMember(
        name: 'Ann',
        enabled: true,
        client: VpsClientRelease(
          version: v,
          url: Uri.parse('https://example.com/setup.exe'),
        ),
      ),
    );
    await _pump(
      tester,
      const VpsUpdateCard(currentVersion: '1.0.0'),
      withClient('1.1.0'),
    );
    expect(find.text('Version 1.1.0 is available'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    await _pump(
      tester,
      const VpsUpdateCard(currentVersion: '1.2.0'),
      withClient('1.1.0'),
    );
    expect(find.byType(Text), findsNothing);
  });
}
