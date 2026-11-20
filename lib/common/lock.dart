import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';

/// Keeps two processes off one data directory. Raising the running window is
/// the platform's job: LaunchServices reopen, GApplication activation, or the
/// rust_api hand-off in the Windows runner.
class SingleInstanceLock {
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;

  SingleInstanceLock._internal();

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  @visibleForTesting
  static Future<String> Function() resolvePath = () => appPath.lockFilePath;

  Future<bool> acquire() async {
    RandomAccessFile? file;
    try {
      final lockFilePath = await resolvePath();
      final lockFile = File(lockFilePath);
      await lockFile.create();
      file = await lockFile.open(mode: FileMode.write);
      await file.lock();
      _accessFile = file;
      return true;
    } catch (e) {
      try {
        await file?.close();
      } catch (_) {}
      commonPrint.log(
        'single instance lock acquire failed ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  @visibleForTesting
  Future<void> release() async {
    await _accessFile?.close();
    _accessFile = null;
  }
}

final singleInstanceLock = SingleInstanceLock();
