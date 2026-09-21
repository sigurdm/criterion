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

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('compare_git', () {
    late File dummyFile;

    setUp(() {
      // Write the dummy benchmark in the project's 'test' folder so it can resolve package imports.
      dummyFile = File('test/temp_compare_git_dummy_bench.dart');
      dummyFile.writeAsStringSync('''
import 'package:criterion/criterion.dart';

void main() async {
  await criterion(
    'DummySuite',
    (c) {
      c.bench(
        'dummy_bench',
        () {
          var a = 0;
          for (var i = 0; i < 100; i++) {
            a += i;
          }
        },
        samples: 5,
        warmupDuration: Duration(milliseconds: 10),
      );
    },
    config: CriterionConfig(
      generateHtmlReport: false,
      exportJson: false,
      exportHistory: false,
      reportDir: 'custom_report_dir',
    ),
  );
}
''');
    });

    tearDown(() {
      try {
        if (dummyFile.existsSync()) {
          dummyFile.deleteSync();
        }
      } catch (e) {
        print('Warning: cleanup failed: $e');
      }
    });

    test('compares HEAD with HEAD', () async {
      final dartExe = Platform.resolvedExecutable;
      final compareGitScript = 'bin/compare_git.dart';

      print('Running compare_git HEAD HEAD ${dummyFile.path}...');
      final result = await Process.run(dartExe, [
        compareGitScript,
        'HEAD',
        'HEAD',
        dummyFile.path,
      ]);

      print('stdout:\n${result.stdout}');
      print('stderr:\n${result.stderr}');

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Time (before)'));
      expect(result.stdout, contains('Time (after)'));
      expect(result.stdout, contains('Significant?'));
      expect(result.stdout, contains('dummy_bench'));
    });

    test('cleans up worktree on invalid ref failure', () async {
      final dartExe = Platform.resolvedExecutable;
      final compareGitScript = 'bin/compare_git.dart';

      await Process.run('git', ['worktree', 'prune']);
      final beforeWorktrees = await Process.run('git', ['worktree', 'list']);
      final result = await Process.run(dartExe, [
        compareGitScript,
        'HEAD',
        'invalid_nonexistent_ref_xyz',
        dummyFile.path,
      ]);
      final afterWorktrees = await Process.run('git', ['worktree', 'list']);

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('Cleaning up worktree at'));
      expect(
        afterWorktrees.stdout,
        equals(beforeWorktrees.stdout),
        reason: 'Worktree list should have no leaked temporary worktrees',
      );
    });
  });
}
