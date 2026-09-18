// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:io';
import '../result.dart';

String get localOs => Platform.operatingSystem;
String get localDartSdkVersion => Platform.version.split(' ').first;

bool get supportsAnsiEscapes =>
    !const bool.fromEnvironment('NO_COLOR') &&
    !Platform.environment.containsKey('NO_COLOR') &&
    stdout.supportsAnsiEscapes;

final GitCommit? localGitCommit = _readGitCommit();

GitCommit? _readGitCommit() {
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
