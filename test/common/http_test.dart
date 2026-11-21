import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

class _FakeCertificate implements X509Certificate {
  @override
  String get issuer => 'CN=Untrusted';

  @override
  String get subject => 'CN=example.com';

  @override
  DateTime get startValidity => DateTime(2026);

  @override
  DateTime get endValidity => DateTime(2027);

  @override
  Uint8List get der => Uint8List(0);

  @override
  String get pem => '';

  @override
  Uint8List get sha1 => Uint8List(0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer buildContainer({
    bool running = true,
    String? currentSsid,
    List<String> excludeSSIDs = const [],
    int mixedPort = 7890,
    bool checkCertificate = true,
  }) {
    final container = ProviderContainer(
      overrides: [excludeSSIDsProvider.overrideWithValue(excludeSSIDs)],
    );
    addTearDown(container.dispose);
    container.read(runTimeProvider.notifier).value = running ? 1 : null;
    container.read(currentSSIDProvider.notifier).value = currentSsid;
    container.read(patchClashConfigProvider.notifier).value =
        const PatchClashConfig().copyWith(mixedPort: mixedPort);
    container.read(appSettingProvider.notifier).value = const AppSettingProps()
        .copyWith(checkCertificate: checkCertificate);
    return container;
  }

  final remote = Uri.parse('https://example.com/path');

  test('loopback traffic always bypasses the proxy', () {
    final container = buildContainer();

    expect(
      FlClashHttpOverrides.findProxyFor(
        container,
        Uri.parse('http://$localhost:9090/ui'),
      ),
      'DIRECT',
    );
  });

  test('bypasses every IPv4 loopback address and localhost name', () {
    final container = buildContainer(mixedPort: 7891);
    for (final host in [
      '127.0.0.2',
      '127.255.255.254',
      '127.0.0.1.',
      '127.0.0.2.',
      'localhost.',
      'LOCALHOST..',
      'api.localhost..',
      'api.localhost',
      'api.localhost.',
      '[::1]',
    ]) {
      final url = Uri.parse('http://$host:9090/health');
      expect(
        FlClashHttpOverrides.findProxyFor(container, url),
        'DIRECT',
        reason: 'Loopback URL must not be proxied: $url',
      );
    }
    for (final host in ['127.0.0.2.example.com', '192.0.2.1', 'example.com']) {
      final url = Uri.parse('https://$host/status');
      expect(
        FlClashHttpOverrides.findProxyFor(container, url),
        'PROXY 127.0.0.1:7891',
        reason: 'Non-loopback host must keep normal routing: $url',
      );
    }
  });

  test('routes through the mixed port while the core is running', () {
    final container = buildContainer(mixedPort: 7891);

    expect(
      FlClashHttpOverrides.findProxyFor(container, remote),
      'PROXY 127.0.0.1:7891',
    );
  });

  test('carries credentials when local authentication is enabled', () {
    final container = buildContainer();
    container.read(networkSettingProvider.notifier).value = const NetworkProps()
        .copyWith(
          authentication: const AuthenticationProps(
            enable: true,
            username: 'user',
            password: 'pass',
          ),
        );

    expect(
      FlClashHttpOverrides.findProxyFor(container, remote),
      'PROXY user:pass@127.0.0.1:7890',
    );

    container.read(networkSettingProvider.notifier).value = const NetworkProps()
        .copyWith(
          authentication: const AuthenticationProps(
            enable: false,
            username: 'user',
          ),
        );
    expect(
      FlClashHttpOverrides.findProxyFor(container, remote),
      'PROXY 127.0.0.1:7890',
    );
  });

  group('local proxy credentials with punctuation (#64)', () {
    const username = 'user@home';
    const password = 'p%@:ss';
    final expected =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';

    ProviderContainer withAuth(
      int port, {
      String user = username,
      String pass = password,
    }) {
      final container = buildContainer(mixedPort: port);
      container.read(networkSettingProvider.notifier).value = NetworkProps()
          .copyWith(
            authentication: AuthenticationProps(
              enable: true,
              username: user,
              password: pass,
            ),
          );
      return container;
    }

    test('are carried verbatim in the proxy string', () {
      expect(
        FlClashHttpOverrides.findProxyFor(withAuth(7890), remote),
        'PROXY $username:$password@127.0.0.1:7890',
      );
      expect(FlClashHttpOverrides.pacUserInfo('a', 'b;c'), isNull);
      expect(FlClashHttpOverrides.pacUserInfo('a', ' b'), isNull);
      expect(FlClashHttpOverrides.pacUserInfo('a', ''), isNull);
      expect(FlClashHttpOverrides.pacUserInfo('a:b', 'c'), isNull);
    });

    test('authenticate an HTTPS tunnel', () async {
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.close);
      final head = Completer<String>();
      proxy.listen((socket) {
        final buffer = StringBuffer();
        socket.listen((data) {
          buffer.write(latin1.decode(data));
          if (buffer.toString().contains('\r\n\r\n') && !head.isCompleted) {
            head.complete(buffer.toString());
            socket.add(
              latin1.encode(
                'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n',
              ),
            );
            unawaited(socket.close());
          }
        });
      });
      final client = FlClashHttpOverrides(
        withAuth(proxy.port),
      ).createHttpClient(null);
      addTearDown(() => client.close(force: true));
      await expectLater(
        client.getUrl(Uri.parse('https://example.invalid/')),
        throwsA(isA<HttpException>()),
      );
      final request = await head.future;
      expect(request, startsWith('CONNECT example.invalid:443'));
      expect(
        request.toLowerCase(),
        contains('proxy-authorization: ${expected.toLowerCase()}'),
      );
    });

    Future<void> streamedPut(
      ProviderContainer Function(int) container,
      String expected,
    ) async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      var challenges = 0;
      final received = <String>[];
      final uploaded = <int>[];
      proxy.listen((request) async {
        final credential = request.headers.value(
          HttpHeaders.proxyAuthorizationHeader,
        );
        if (credential == null) {
          challenges++;
          request.response
            ..statusCode = HttpStatus.proxyAuthenticationRequired
            ..headers.set(
              HttpHeaders.proxyAuthenticateHeader,
              'Basic realm="local-test"',
            );
        } else {
          received.add(credential);
          await for (final chunk in request) {
            uploaded.addAll(chunk);
          }
          request.response.statusCode = credential == expected
              ? HttpStatus.ok
              : HttpStatus.forbidden;
        }
        await request.response.close();
      });
      final client = FlClashHttpOverrides(
        container(proxy.port),
      ).createHttpClient(null);
      addTearDown(() => client.close(force: true));
      final request = await client.openUrl(
        'PUT',
        Uri.parse('http://example.invalid/proxy-check'),
      );
      request.add([1, 2, 3, 4, 5]);
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.ok);
      expect(challenges, 0);
      expect(received, [expected]);
      expect(uploaded, [1, 2, 3, 4, 5]);
    }

    test('authenticate a streamed plain-HTTP upload up front', () async {
      await streamedPut(withAuth, expected);
    });

    test(
      'the proxy string cannot carry still reach a plain-HTTP proxy',
      () async {
        await streamedPut(
          (port) => withAuth(port, pass: 'semi;colon'),
          'Basic ${base64Encode(utf8.encode('$username:semi;colon'))}',
        );
      },
    );
  });

  test('bypasses the proxy when the core is not running', () {
    final container = buildContainer(running: false);

    expect(FlClashHttpOverrides.findProxyFor(container, remote), 'DIRECT');
  });

  test('bypasses the proxy on an excluded SSID', () {
    final container = buildContainer(
      currentSsid: 'Office Wi-Fi',
      excludeSSIDs: const ['Office Wi-Fi'],
    );

    expect(FlClashHttpOverrides.findProxyFor(container, remote), 'DIRECT');
  });

  test('keeps proxying when the current SSID is not excluded', () {
    final container = buildContainer(
      currentSsid: 'Home Wi-Fi',
      excludeSSIDs: const ['Office Wi-Fi'],
    );

    expect(
      FlClashHttpOverrides.findProxyFor(container, remote),
      'PROXY 127.0.0.1:7890',
    );
  });

  test('an untrusted certificate is rejected by default', () {
    final container = buildContainer();

    expect(
      FlClashHttpOverrides.allowBadCertificate(
        container,
        _FakeCertificate(),
        'example.com',
        443,
      ),
      isFalse,
    );
  });

  test('turning the check off accepts an untrusted certificate', () {
    final container = buildContainer(checkCertificate: false);

    expect(
      FlClashHttpOverrides.allowBadCertificate(
        container,
        _FakeCertificate(),
        'example.com',
        443,
      ),
      isTrue,
    );
  });
}
