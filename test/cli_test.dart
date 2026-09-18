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
import 'package:test/test.dart';

void main() {
  final dartExe = Platform.resolvedExecutable;

  group('CLI help and argument validation', () {
    for (final script in [
      'bin/run.dart',
      'bin/compare.dart',
      'bin/compare_git.dart',
      'bin/graph.dart',
    ]) {
      test('$script --help and -h exit 0 and print usage', () async {
        for (final flag in ['--help', '-h']) {
          final result = await Process.run(dartExe, [script, flag]);
          expect(
            result.exitCode,
            equals(0),
            reason: '$script $flag failed: ${result.stderr}',
          );
          expect(result.stdout as String, contains('Usage:'));
        }
      });

      test('$script rejects unknown flags with exit code 64', () async {
        final result = await Process.run(dartExe, [
          script,
          '--definitely-not-a-valid-flag',
        ]);
        expect(result.exitCode, equals(64));
      });
    }

    test(
      'bin/run.dart rejects non-numeric --samples and --noise-threshold',
      () async {
        final badSamples = await Process.run(dartExe, [
          'bin/run.dart',
          '--samples=abc',
        ]);
        expect(badSamples.exitCode, equals(64));
        expect(badSamples.stderr as String, contains('Invalid --samples'));

        final badNoise = await Process.run(dartExe, [
          'bin/run.dart',
          '--noise-threshold=xyz',
        ]);
        expect(badNoise.exitCode, equals(64));
        expect(
          badNoise.stderr as String,
          contains('Invalid --noise-threshold'),
        );
      },
    );

    test(
      'bin/graph.dart exits 1 with clean message on malformed history JSON',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('criterion_graph_');
        try {
          final corrupt = File('${tempDir.path}/corrupt.json')
            ..writeAsStringSync('{not valid json');
          final result = await Process.run(dartExe, [
            'bin/graph.dart',
            '--history=${corrupt.path}',
          ]);
          expect(result.exitCode, equals(1));
          expect(
            result.stderr as String,
            contains('Error parsing history file'),
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test(
      'bin/compare_git.dart rejects benchmark path outside git root',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'criterion_outside_',
        );
        try {
          final outsideFile = File('${tempDir.path}/outside_bench.dart')
            ..writeAsStringSync('void main() {}');
          final result = await Process.run(dartExe, [
            'bin/compare_git.dart',
            'HEAD',
            'HEAD',
            outsideFile.path,
          ]);
          expect(result.exitCode, equals(1));
          expect(
            result.stderr as String,
            contains('must be inside the git repository'),
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });
}
