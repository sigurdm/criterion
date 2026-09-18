import 'dart:io';
import '../result.dart';

String get localOs => Platform.operatingSystem;
String get localDartSdkVersion => Platform.version.split(' ').first;

GitCommit? get localGitCommit {
  try {
    final result = Process.runSync('git', [
      'log',
      '-1',
      '--format=%H%x1f%h%x1f%s%x1f%cI',
    ]);
    if (result.exitCode == 0) {
      final parts = (result.stdout as String).trim().split('\x1f');
      if (parts.length >= 4) {
        final hash = parts[0].trim();
        final shortHash = parts[1].trim();
        final message = parts[2].trim();
        final dateStr = parts[3].trim();
        final timestamp = DateTime.tryParse(dateStr);
        if (hash.isNotEmpty) {
          return GitCommit(
            hash: hash,
            shortHash: shortHash,
            message: message,
            timestamp: timestamp,
          );
        }
      }
    }
  } catch (_) {}
  return null;
}
