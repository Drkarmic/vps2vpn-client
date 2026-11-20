import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua => [
    '$appName/v$version',
    'clash-verge',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

final _versionPattern = RegExp(
  r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$',
);

final class _ParsedVersion {
  const _ParsedVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.prerelease,
    this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final String? prerelease;
  final String? build;

  static _ParsedVersion? tryParse(String raw) {
    final match = _versionPattern.firstMatch(raw.trim());
    if (match == null) {
      return null;
    }
    final major = int.tryParse(match.group(1)!);
    final minor = match.group(2) == null ? 0 : int.tryParse(match.group(2)!);
    final patch = match.group(3) == null ? 0 : int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) {
      return null;
    }
    return _ParsedVersion(
      major: major,
      minor: minor,
      patch: patch,
      prerelease: match.group(4),
      build: match.group(5),
    );
  }
}

int _comparePrerelease(String? a, String? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final aParts = a.split('.');
  final bParts = b.split('.');
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final ap = aParts[i];
    final bp = bParts[i];
    if (ap == bp) continue;
    final ai = int.tryParse(ap);
    final bi = int.tryParse(bp);
    if (ai != null && bi != null) {
      return ai.compareTo(bi);
    }
    if (ai != null) return -1;
    if (bi != null) return 1;
    return ap.compareTo(bp);
  }
  return aParts.length.compareTo(bParts.length);
}

int _compareBuild(String? a, String? b) {
  if (a == b) return 0;
  final ai = a == null ? 0 : int.tryParse(a);
  final bi = b == null ? 0 : int.tryParse(b);
  if (ai != null && bi != null) {
    return ai.compareTo(bi);
  }
  return (a ?? '').compareTo(b ?? '');
}

int compareVersions(String version1, String version2) {
  final v1 = _ParsedVersion.tryParse(version1);
  final v2 = _ParsedVersion.tryParse(version2);
  if (v1 == null && v2 == null) {
    return 0;
  }
  if (v1 == null) {
    return -1;
  }
  if (v2 == null) {
    return 1;
  }
  if (v1.major != v2.major) {
    return v1.major.compareTo(v2.major);
  }
  if (v1.minor != v2.minor) {
    return v1.minor.compareTo(v2.minor);
  }
  if (v1.patch != v2.patch) {
    return v1.patch.compareTo(v2.patch);
  }
  final prereleaseOrder = _comparePrerelease(v1.prerelease, v2.prerelease);
  if (prereleaseOrder != 0) {
    return prereleaseOrder;
  }
  return _compareBuild(v1.build, v2.build);
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
