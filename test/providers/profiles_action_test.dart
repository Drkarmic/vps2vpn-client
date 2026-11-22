import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.answer);

  ResponseBody Function() answer;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return answer();
  }

  @override
  void close({bool force = false}) {}
}

class _UrlAdapter implements HttpClientAdapter {
  _UrlAdapter(this.answer);

  final Future<String> Function(String uri) answer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(await answer(options.uri.toString()), 200);

  @override
  void close({bool force = false}) {}
}

ResponseBody _refused() => throw const SocketException('Connection refused');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late _MockCoreHandlerInterface core;
  late ProviderContainer container;

  setUpAll(() async {
    loadAppLocalizations(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-profiles-action-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    core = _MockCoreHandlerInterface();
    when(() => core.validateConfig(any())).thenAnswer((_) async => null);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
  });

  void decodesTo(String link, List<Map<String, dynamic>> proxies) {
    when(
      () => core.decodeShareLinks([link]),
    ).thenAnswer((_) async => [proxies]);
  }

  Future<void> pumpHost(WidgetTester tester) async {
    const size = Size(1200, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: SizedBox()),
      ),
    );
  }

  Future<List<Map>> savedProxies(Profile profile) async {
    final config = loadYaml(await (await profile.file).readAsString()) as Map;
    return [for (final proxy in config['proxies'] as List) proxy as Map];
  }

  group('addProfileFromLink with a share link', () {
    test('saves a file profile named after the proxy it holds', () async {
      const link = 'vless://id@hk.example.com:443#HK';
      decodesTo(link, [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(profile.url, isEmpty);
      expect(profile.label, 'HK');
      expect(await savedProxies(profile), [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);
      verify(() => core.validateConfig(any())).called(1);
    });

    test('names an unnamed proxy after its server', () async {
      const link = 'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388';
      decodesTo(link, [
        {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link, label: 'Mine');

      final profile = container.read(profilesProvider).single;
      expect(profile.label, 'Mine');
      expect((await savedProxies(profile)).single['name'], 'ss.example.com');
    });

    test('moves a proxy off a name mihomo reserves', () async {
      const link = 'trojan://pass@t.example.com:443#DIRECT';
      decodesTo(link, [
        {'name': 'DIRECT', 'type': 'trojan', 'server': 't.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect((await savedProxies(profile)).single['name'], 'DIRECT-01');
    });

    testWidgets('reports a link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      const link = 'vmess://not-base64';
      decodesTo(link, const []);
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text(currentAppLocalizations.shareLinksInvalid), findsOne);
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });

  group('addProfilesFromLinks with share links', () {
    const links = [
      'vless://id@hk.example.com:443#HK',
      'trojan://pass@hk2.example.com:443#HK',
      'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388',
    ];

    test('makes one profile of all their proxies', () async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          [
            {'name': 'HK', 'type': 'trojan', 'server': 'hk2.example.com'},
          ],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(
        profile.label,
        currentAppLocalizations.proxiesProfileLabel('HK', 3),
      );
      expect(
        [for (final proxy in await savedProxies(profile)) proxy['name']],
        ['HK', 'HK-01', 'ss.example.com'],
      );
      verify(() => core.decodeShareLinks(links)).called(1);
    });

    testWidgets('names the link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          const [],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final l10n = currentAppLocalizations;
      expect(
        find.text(
          l10n.failedItem(links.first, l10n.shareLinkUnreadable(links[1])),
        ),
        findsOne,
      );
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });

  test('a first download a setup asks for waits behind a URL change and '
      'keeps it', () async {
    final answers = <String, Completer<String>>{
      'https://sub.example.com/new': Completer(),
    };
    final fetched = <String>[];
    final adapter = _UrlAdapter((uri) {
      fetched.add(uri);
      return answers[uri]!.future;
    });
    final clashAdapter = request.clashDio.httpClientAdapter;
    final directAdapter = request.directDio.httpClientAdapter;
    addTearDown(() {
      request.clashDio.httpClientAdapter = clashAdapter;
      request.directDio.httpClientAdapter = directAdapter;
    });
    request
      ..attach(container.read)
      ..clashDio.httpClientAdapter = adapter
      ..directDio.httpClientAdapter = adapter;
    final action = container.read(profilesActionProvider.notifier);
    final first = Profile.normal(
      label: 'Sub',
      url: 'https://sub.example.com/old',
    );
    container.read(profilesProvider.notifier).put(first);

    final edit = action.updateProfile(
      first.copyWith(url: 'https://sub.example.com/new'),
    );
    await pumpEventQueue();
    final setup = action.downloadMissingProfile(first);
    answers['https://sub.example.com/new']!.complete('proxies: [new]');
    await edit;
    final used = await setup;

    expect(fetched, ['https://sub.example.com/new']);
    expect(used?.url, 'https://sub.example.com/new');
    final saved = container.read(profilesProvider).getProfile(first.id)!;
    expect(saved.url, 'https://sub.example.com/new');
    expect(await (await saved.file).readAsString(), 'proxies: [new]');
  });

  group('autoUpdateProfiles', () {
    late _RouteAdapter proxied;
    late _RouteAdapter direct;
    late DateTime now;
    late Profile profile;

    setUp(() async {
      final clashAdapter = request.clashDio.httpClientAdapter;
      final directAdapter = request.directDio.httpClientAdapter;
      addTearDown(() {
        request.clashDio.httpClientAdapter = clashAdapter;
        request.directDio.httpClientAdapter = directAdapter;
      });
      proxied = _RouteAdapter(_refused);
      direct = _RouteAdapter(_refused);
      request
        ..attach(container.read)
        ..clashDio.httpClientAdapter = proxied
        ..directDio.httpClientAdapter = direct;
      container.read(runTimeProvider.notifier).value = 1;
      now = DateTime(2026, 11, 20, 8);
      container
          .read(profilesActionProvider.notifier)
          .autoUpdateBackoff
          .now = () =>
          now;
      profile = Profile.normal(label: 'Sub', url: 'https://sub.example.com/t');
      await (await profile.file).writeAsString('proxies: [old]');
      container.read(profilesProvider.notifier).put(profile);
    });

    Future<String> saved() async => (await profile.file).readAsString();

    test('fetches directly when the proxied route is dead', () async {
      direct.answer = () => ResponseBody.fromString('proxies: [new]', 200);

      await container
          .read(profilesActionProvider.notifier)
          .autoUpdateProfiles();

      expect((proxied.calls, direct.calls), (1, 1));
      expect(await saved(), 'proxies: [new]');
      expect(container.read(profilesProvider).single.lastUpdateDate, isNotNull);
    });

    test('does not retry a link the server refuses', () async {
      proxied.answer = () => ResponseBody.fromString('', 403);

      await container
          .read(profilesActionProvider.notifier)
          .autoUpdateProfiles();

      expect((proxied.calls, direct.calls), (1, 0));
      expect(await saved(), 'proxies: [old]');
    });

    test('keeps the last config when the download is empty', () async {
      proxied.answer = () => ResponseBody.fromString(' \r\n', 200);

      await container
          .read(profilesActionProvider.notifier)
          .autoUpdateProfiles();

      expect(await saved(), 'proxies: [old]');
      expect(container.read(profilesProvider).single, profile);
      verifyNever(() => core.validateConfig(any()));
    });

    testWidgets('keeps the last config and says so when both routes fail', (
      tester,
    ) async {
      await pumpHost(tester);
      final action = container.read(profilesActionProvider.notifier);
      final notice = currentAppLocalizations.subscriptionUpdateKeptLast('Sub');

      await tester.runAsync(action.autoUpdateProfiles);
      await tester.pump();

      expect((proxied.calls, direct.calls), (1, 1));
      expect(find.text(notice), findsNothing);

      now = now.add(AutoUpdateBackoff.firstDelay);
      await tester.runAsync(action.autoUpdateProfiles);
      await tester.pump();

      expect((proxied.calls, direct.calls), (2, 2));
      expect(find.text(notice), findsOne);
      expect(await tester.runAsync(saved), 'proxies: [old]');
      expect(container.read(profilesProvider).single, profile);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('backs off after each failure until one succeeds', () async {
      final action = container.read(profilesActionProvider.notifier);

      await action.autoUpdateProfiles();
      await action.autoUpdateProfiles();
      expect(proxied.calls, 1);

      now = now.add(AutoUpdateBackoff.firstDelay);
      await action.autoUpdateProfiles();
      expect(proxied.calls, 2);

      now = now.add(AutoUpdateBackoff.firstDelay);
      await action.autoUpdateProfiles();
      expect(proxied.calls, 2);

      now = now.add(AutoUpdateBackoff.firstDelay);
      direct.answer = () => ResponseBody.fromString('proxies: [new]', 200);
      await action.autoUpdateProfiles();
      expect(proxied.calls, 3);
      expect(action.autoUpdateBackoff.failures(profile.id), 0);
    });
  });
}
