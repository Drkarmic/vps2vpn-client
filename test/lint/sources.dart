import 'dart:io';

import 'package:path/path.dart' as p;

const sourceRoots = ['lib'];

/// [path] relative to the repository with `/` between its parts on every
/// platform, the form the allowlists and the `/generated/` checks are written
/// in.
String sourcePath(String path) => p.split(p.relative(path)).join('/');

/// Everything under [root], each named by its [sourcePath].
List<FileSystemEntity> listSources(String root) => [
  for (final entity in Directory(root).listSync(recursive: true))
    switch (entity) {
      File() => File(sourcePath(entity.path)),
      Directory() => Directory(sourcePath(entity.path)),
      _ => entity,
    },
];

List<FileSystemEntity> sourceEntities() => [
  for (final root in sourceRoots) ...listSources(root),
];
