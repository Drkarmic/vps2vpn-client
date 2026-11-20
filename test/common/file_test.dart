import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('safeDeletePath', () {
    test('removes a file', () async {
      final path = join(root.path, 'config.yaml');
      File(path).writeAsStringSync('mixed-port: 7890');

      await safeDeletePath(path);

      expect(File(path).existsSync(), isFalse);
    });

    test('removes a directory along with everything under it', () async {
      final path = join(root.path, '42');
      File(join(path, 'proxies', 'abc'))
        ..createSync(recursive: true)
        ..writeAsStringSync('proxies: []');

      await safeDeletePath(path);

      expect(Directory(path).existsSync(), isFalse);
    });

    test('accepts a path that is already gone', () async {
      await expectLater(safeDeletePath(join(root.path, 'missing')), completes);
    });
  });

  group('writeAsStringAtomically', () {
    test('replaces the file and leaves nothing beside it', () async {
      final file = File(join(root.path, 'config.yaml'))
        ..writeAsStringSync('mixed-port: 7890');

      await file.writeAsStringAtomically('mixed-port: 7891');

      expect(file.readAsStringSync(), 'mixed-port: 7891');
      expect(root.listSync().map((entry) => basename(entry.path)), [
        'config.yaml',
      ]);
    });

    test('creates the directory a first write needs', () async {
      final file = File(join(root.path, 'home', 'config.yaml'));

      await file.writeAsStringAtomically('mode: rule');

      expect(file.readAsStringSync(), 'mode: rule');
    });

    test('failed replacement cleans staged files without deleting the target', () async {
      final path = join(root.path, 'config.yaml');
      final target = Directory(path)..createSync();

      await expectLater(
        File(path).writeAsStringAtomically('mode: global'),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.existsSync(), isTrue);
      expect(root.listSync().map((entity) => basename(entity.path)), [
        'config.yaml',
      ]);
    });

    test('overlapping writes never share a temporary sibling', () async {
      final file = File(join(root.path, 'config.yaml'));
      final values = List.generate(16, (i) => 'entry-$i:' + ('x' * 32768));

      await Future.wait(values.map(file.writeAsStringAtomically));

      expect(values, contains(file.readAsStringSync()));
      expect(root.listSync().map((entity) => basename(entity.path)), [
        'config.yaml',
      ]);
    });

    test('a stale legacy staging directory cannot block later writes', () async {
      final file = File(join(root.path, 'config.yaml'));
      final legacyStaging = Directory('${file.path}.$pid.tmp')..createSync();
      await file.writeAsStringAtomically('mode: rule');

      expect(file.readAsStringSync(), 'mode: rule');
      expect(legacyStaging.existsSync(), isTrue);
    });
  });
}
