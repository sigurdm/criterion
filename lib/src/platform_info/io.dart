import 'dart:io';
import '../result.dart';

String get localOs => Platform.operatingSystem;
String get localDartSdkVersion => Platform.version.split(' ').first;

GitCommit? get localGitCommit {
  try {
    final result = Process.runSync('git', [
      'log',
      '-1',
      '--format=%H%n%h%n%s%n%cI',
    ]);
    if (result.exitCode == 0) {
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length >= 4) {
        final hash = lines[0].trim();
        final shortHash = lines[1].trim();
        final message = lines[2].trim();
        final dateStr = lines[3].trim();
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
