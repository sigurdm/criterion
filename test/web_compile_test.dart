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
  group('Web and Wasm compilation parity', () {
    late File entryFile;
    late Directory outDir;

    setUpAll(() {
      entryFile = File('test/temp_web_parity_entry.dart');
      outDir = Directory.systemTemp.createTempSync('criterion_web_parity_');
      entryFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

Future<void> main() async {
  await criterion(
    'WebParitySuite',
    (c) {
      c.bench('noop', () => blackhole(blackbox(42)), samples: 5);
      c.benchState<List<int>>(
        'sort',
        (list) => list.sort(),
        setup: () => [3, 1, 2],
        batchSize: BatchSize.smallInput,
        samples: 5,
      );
    },
    config: const CriterionConfig(
      exportJson: false,
      generateHtmlReport: false,
      exportHistory: false,
    ),
  );
}
''');
    });

    tearDownAll(() {
      if (entryFile.existsSync()) {
        entryFile.deleteSync();
      }
      if (outDir.existsSync()) {
        outDir.deleteSync(recursive: true);
      }
    });

    test('compiles cleanly with dart compile js', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        entryFile.path,
        '-o',
        '${outDir.path}/out.js',
      ]);
      expect(
        result.exitCode,
        equals(0),
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    });

    test('compiles cleanly with dart compile wasm', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'wasm',
        entryFile.path,
        '-o',
        '${outDir.path}/out.wasm',
      ]);
      expect(
        result.exitCode,
        equals(0),
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    });
  });
}
