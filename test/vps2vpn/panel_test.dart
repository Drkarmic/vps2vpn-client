import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/vps2vpn/panel.dart';
import 'package:flutter_test/flutter_test.dart';

const _tok = 'AbCdEf0123456789xyzQ';

void main() {
  group('api base', () {
    test('drops the query and adds /api/', () {
      expect(
        vpsApiBase('https://1.2.3.4:43470/s/$_tok?format=clash').toString(),
        'https://1.2.3.4:43470/s/$_tok/api/',
      );
      expect(
        vpsApiBase('http://1.2.3.4:43470/s/$_tok').toString(),
        'http://1.2.3.4:43470/s/$_tok/api/',
      );
    });

    test('ignores links that are not vps2vpn subscriptions', () {
      expect(vpsApiBase(''), isNull);
      expect(vpsApiBase('https://example.com/sub?token=$_tok'), isNull);
      expect(vpsApiBase('https://example.com/s/short'), isNull);
      expect(vpsApiBase('https://example.com/s/$_tok/extra'), isNull);
      expect(vpsApiBase('clash://install-config?url=x'), isNull);
    });
  });

  test('reads the member fields the panel sends', () {
    final m = VpsMember.fromJson({
      'name': 'Ann',
      'enabled': false,
      'disabled_reason': 'quota',
      'used_up': 100,
      'used_down': 400,
      'quota_gb': 10,
      'quota_eff': 15,
      'expire_at': 1893456000,
      'ai': {
        'summary': 'Claude ok',
        'place': 'Singapore',
        'at': 1893456000,
        'sites': {'claude': 'ok', 'chatgpt': 'blocked'},
      },
    });
    expect(m.enabled, isFalse);
    expect(m.disabledReason, 'quota');
    expect(m.used, 500);
    expect(m.quotaGb, 15);
    expect(m.expireAt!.millisecondsSinceEpoch, 1893456000 * 1000);
    expect(m.ai!.sites, {'claude': 'ok', 'chatgpt': 'blocked'});
    expect(VpsMember.fromJson({'ai': null, 'expire_at': 0}).ai, isNull);
    expect(VpsMember.fromJson({'expire_at': 0}).expireAt, isNull);
  });

  test('names the line kinds the panel knows', () {
    expect(vpsLineKind({'type': 'hysteria2'}), 'hy2');
    expect(vpsLineKind({'type': 'tuic'}), 'tuic');
    expect(
      vpsLineKind({
        'type': 'vless',
        'reality-opts': {'public-key': 'k'},
      }),
      'reality',
    );
    expect(vpsLineKind({'type': 'vless'}), isNull);
    expect(vpsLineKind({'type': 'ss'}), isNull);
  });

  test('reports a line once when it keeps failing and once when back', () {
    final h = VpsLineHealth(threshold: 3);
    expect(h.record('hy2@a', false), isNull);
    expect(h.record('hy2@a', true), isNull, reason: 'a blip says nothing');
    expect(h.record('hy2@a', false), isNull);
    expect(h.record('hy2@a', false), isNull);
    expect(h.record('hy2@a', false), isFalse);
    expect(h.record('hy2@a', false), isNull, reason: 'already reported');
    expect(h.record('tuic@a', false), isNull, reason: 'lines are separate');
    expect(h.record('hy2@a', true), isTrue);
    expect(h.record('hy2@a', true), isNull);
  });

  group('against a local panel', () {
    late HttpServer server;
    final posts = <(String?, Object?)>[];
    var meStatus = HttpStatus.ok;

    setUp(() async {
      posts.clear();
      meStatus = HttpStatus.ok;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        if (path == '/s/$_tok/api/me' && req.method == 'GET') {
          req.response.statusCode = meStatus;
          req.response.write(jsonEncode({'name': 'Ann', 'enabled': true}));
        } else if (path == '/s/$_tok/api/report' && req.method == 'POST') {
          posts.add((
            req.headers.value('X-V2V'),
            jsonDecode(await utf8.decodeStream(req)),
          ));
          req.response.write('{"ok":true}');
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri base() => vpsApiBase('http://127.0.0.1:${server.port}/s/$_tok')!;

    test('fetches the member', () async {
      final r = await fetchMember(base());
      expect(r!.member!.name, 'Ann');
      expect(r.linkChanged, isFalse);
    });

    test('a 404 means the link was replaced', () async {
      meStatus = HttpStatus.notFound;
      final r = await fetchMember(base());
      expect(r!.linkChanged, isTrue);
    });

    test('a report carries the header and the line', () async {
      expect(
        await reportLine(base(), line: 'hy2', ok: false, host: '1.2.3.4'),
        isTrue,
      );
      expect(posts.single.$1, '1');
      expect(posts.single.$2, {'line': 'hy2', 'ok': false, 'host': '1.2.3.4'});
    });
  });
}
