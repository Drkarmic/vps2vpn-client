import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/webdav.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final ResponseBody Function(RequestOptions options) _responses;
  final List<RequestOptions> requests = [];
  final List<List<int>> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      requestBodies.add(bytes);
    }
    return _responses(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_ScriptedAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  test(
    'redirect to a different origin drops the Authorization header',
    () async {
      var call = 0;
      final adapter = _ScriptedAdapter((options) {
        call++;
        if (call == 1) {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['http://other.example/target'],
            },
          );
        }
        return ResponseBody.fromString('', 204);
      });
      final transport = DAVTransport(
        uri: 'http://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await transport.options('probe');

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].headers, contains('authorization'));
      expect(adapter.requests[1].uri.host, 'other.example');
      expect(adapter.requests[1].headers, isNot(contains('authorization')));
    },
  );

  test(
    'a foreign Digest challenge cannot override origin authentication',
    () async {
      var calls = 0;
      final adapter = _ScriptedAdapter((_) {
        calls++;
        return switch (calls) {
          1 => ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://other.example/probe'],
            },
          ),
          2 => ResponseBody.fromString(
            '',
            401,
            headers: {
              'www-authenticate': [
                'Digest realm="foreign", nonce="attacker", qop="auth"',
              ],
            },
          ),
          _ => ResponseBody.fromString('', 204),
        };
      });
      final transport = DAVTransport(
        uri: 'https://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await expectLater(
        transport.options('probe'),
        throwsA(isA<DAVException>()),
      );

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].uri.host, 'other.example');
      expect(adapter.requests[1].headers, isNot(contains('authorization')));

      // A later request must still use origin credentials, not the
      // challenge supplied by the redirected third-party host.
      await transport.options('probe');
      expect(adapter.requests, hasLength(3));
      expect(
        adapter.requests.last.headers['authorization'],
        startsWith('Basic '),
      );
    },
  );

  test(
    'an off-origin challenge does not replace an existing trusted Digest',
    () async {
      var calls = 0;
      final adapter = _ScriptedAdapter((_) {
        calls++;
        return switch (calls) {
          1 => ResponseBody.fromString(
            '',
            401,
            headers: {
              'www-authenticate': [
                'Digest realm="trusted", nonce="first", qop="auth"',
              ],
            },
          ),
          3 => ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://foreign.example/'],
            },
          ),
          4 => ResponseBody.fromString(
            '',
            401,
            headers: {
              'www-authenticate': [
                'Digest realm="foreign", nonce="second", qop="auth"',
              ],
            },
          ),
          _ => ResponseBody.fromString('', 204),
        };
      });
      final transport = DAVTransport(
        uri: 'https://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await transport.options('first');
      expect(
        adapter.requests[1].headers['authorization'],
        contains('realm="trusted"'),
      );

      await expectLater(
        transport.options('foreign'),
        throwsA(isA<DAVException>()),
      );
      await transport.options('next');
      expect(adapter.requests, hasLength(5));
      expect(
        adapter.requests.last.headers['authorization'],
        contains('realm="trusted"'),
      );
      expect(
        adapter.requests.last.headers['authorization'],
        isNot(contains('realm="foreign"')),
      );
    },
  );

  test(
    'redirect within the same origin keeps the Authorization header',
    () async {
      var call = 0;
      final adapter = _ScriptedAdapter((options) {
        call++;
        if (call == 1) {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['http://origin.example/base/moved'],
            },
          );
        }
        return ResponseBody.fromString('', 204);
      });
      final transport = DAVTransport(
        uri: 'http://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await transport.options('probe');

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].headers, contains('authorization'));
    },
  );

  test(
    'a Digest challenge is found even behind a Basic www-authenticate line',
    () async {
      var call = 0;
      final adapter = _ScriptedAdapter((options) {
        call++;
        if (call == 1) {
          return ResponseBody.fromString(
            '',
            401,
            headers: {
              'www-authenticate': [
                'Basic realm="x"',
                'Digest realm="y", nonce="abc123", qop="auth", opaque="op1"',
              ],
            },
          );
        }
        return ResponseBody.fromString('', 204);
      });
      final transport = DAVTransport(
        uri: 'http://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await transport.options('probe');

      expect(adapter.requests, hasLength(2));
      final retryAuth = adapter.requests[1].headers['authorization'] as String;
      expect(retryAuth, startsWith('Digest '));
      expect(retryAuth, contains('realm="y"'));
    },
  );

  for (final method in ['MKCOL', 'PUT', 'GET']) {
    test('$method does not follow a redirect to another origin', () async {
      final adapter = _ScriptedAdapter(
        (options) => options.uri.host == 'origin.example'
            ? ResponseBody.fromString(
                '',
                307,
                headers: {
                  'location': ['https://other.example/created'],
                },
              )
            : ResponseBody.fromString('', 201),
      );
      final transport = DAVTransport(
        uri: 'https://origin.example/base',
        user: 'user',
        password: 'pass',
        dio: _dioWith(adapter),
      );

      await expectLater(switch (method) {
        'MKCOL' => transport.mkcol('backups'),
        'PUT' => transport.put('backups/a.zip', [1]),
        _ => transport.get('backups/a.zip'),
      }, throwsA(isA<DAVException>()));
      expect(adapter.requests, hasLength(1));
    });
  }

  test('MKCOL follows a redirect within the origin', () async {
    final adapter = _ScriptedAdapter(
      (options) => options.uri.path == '/base/backups/'
          ? ResponseBody.fromString(
              '',
              301,
              headers: {
                'location': ['/base/Backups/'],
              },
            )
          : ResponseBody.fromString('', 201),
    );
    final transport = DAVTransport(
      uri: 'https://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );

    await transport.mkcol('backups');

    expect(adapter.requests.map((r) => r.method), ['MKCOL', 'MKCOL']);
    expect(adapter.requests[1].uri.path, '/base/Backups/');
    expect(adapter.requests[1].headers, contains('authorization'));
  });

  DAVTransport partialTransport(String contentRange) {
    final adapter = _ScriptedAdapter(
      (options) => ResponseBody.fromBytes(
        [1, 2, 3, 4],
        206,
        headers: {
          'content-range': [contentRange],
        },
      ),
    );
    return DAVTransport(
      uri: 'http://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );
  }

  test('a 206 that spans the whole object is read as the file', () async {
    final bytes = await partialTransport('bytes 0-3/4').get('backup.zip');

    expect(bytes, [1, 2, 3, 4]);
  });

  test('the bytes unit in Content-Range is case-insensitive', () async {
    final bytes = await partialTransport('Bytes 0-3/4').get('backup.zip');

    expect(bytes, [1, 2, 3, 4]);
  });

  test('a 206 that covers only part of the object fails', () async {
    await expectLater(
      partialTransport('bytes 0-3/10').get('backup.zip'),
      throwsA(isA<DAVException>()),
    );
  });

  test('file PUT retries a fresh stream after Digest challenge', () async {
    final dir = await Directory.systemTemp.createTemp('v2v-dav-put-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/backup.zip');
    await file.writeAsBytes([1, 2, 3, 4, 5]);
    var calls = 0;
    final adapter = _ScriptedAdapter((_) {
      calls++;
      if (calls == 1) {
        return ResponseBody.fromString(
          '',
          401,
          headers: {
            'www-authenticate': [
              'Digest realm="test", nonce="abcdef", qop="auth"',
            ],
          },
        );
      }
      return ResponseBody.fromString('', 201);
    });
    final transport = DAVTransport(
      uri: 'https://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );

    await transport.putFile('backup.zip', file.path);

    expect(calls, 2);
    expect(adapter.requestBodies, [
      [1, 2, 3, 4, 5],
      [1, 2, 3, 4, 5],
    ]);
    expect(adapter.requests[1].headers['authorization'], startsWith('Digest '));
    expect(adapter.requests[1].headers[Headers.contentLengthHeader], 5);
  });

  test('streamed GET rejects unknown-length overflow and retains the old file', () async {
    final dir = await Directory.systemTemp.createTemp('v2v-dav-cap-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/backup.zip');
    await file.writeAsString('original');
    final adapter = _ScriptedAdapter(
      (_) => ResponseBody(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5, 6]),
        ]),
        200,
      ),
    );
    final transport = DAVTransport(
      uri: 'https://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );

    await expectLater(
      transport.getFile('backup.zip', file.path, maxBytes: 4),
      throwsA(isA<DAVException>()),
    );
    expect(await file.readAsString(), 'original');
    expect(await dir.list().toList(), hasLength(1));
  });

  test('streamed GET rejects oversized declared length before writing', () async {
    final dir = await Directory.systemTemp.createTemp('v2v-dav-length-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/backup.zip');
    await file.writeAsString('original');
    final adapter = _ScriptedAdapter(
      (_) => ResponseBody.fromBytes(
        [1, 2, 3],
        200,
        headers: {'content-length': ['999999999']},
      ),
    );
    final transport = DAVTransport(
      uri: 'https://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );

    await expectLater(
      transport.getFile('backup.zip', file.path, maxBytes: 4),
      throwsA(isA<DAVException>()),
    );
    expect(await file.readAsString(), 'original');
    expect(await dir.list().toList(), hasLength(1));
  });

  test('streamed GET writes a complete 206 but rejects partial range', () async {
    final dir = await Directory.systemTemp.createTemp('v2v-dav-range-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/backup.zip');
    await file.writeAsString('original');
    var calls = 0;
    final adapter = _ScriptedAdapter((_) {
      calls++;
      return ResponseBody.fromBytes(
        [1, 2, 3, 4],
        206,
        headers: {
          'content-range': [calls == 1 ? 'bytes 0-3/8' : 'bytes 0-3/4'],
        },
      );
    });
    final transport = DAVTransport(
      uri: 'https://origin.example/base',
      user: 'user',
      password: 'pass',
      dio: _dioWith(adapter),
    );

    await expectLater(
      transport.getFile('backup.zip', file.path, maxBytes: 8),
      throwsA(isA<DAVException>()),
    );
    expect(await file.readAsString(), 'original');
    expect(await dir.list().toList(), hasLength(1));

    await transport.getFile('backup.zip', file.path, maxBytes: 8);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });
}
