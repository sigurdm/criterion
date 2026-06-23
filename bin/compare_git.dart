// Copyright 2026 Sigurd Meldgaard
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

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:criterion/criterion.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
      'Usage: dart run bin/compare_git.dart <ref1> <ref2> <benchmark_file.dart> [extra_args...]',
    );
    exit(1);
  }

  final ref1 = args[0];
  final ref2 = args[1];
  final benchmarkFileVal = args[2];
  final extraArgs = args.sublist(3);

  final benchmarkFile = File(benchmarkFileVal);
  if (!benchmarkFile.existsSync()) {
    stderr.writeln('Error: Benchmark file does not exist: $benchmarkFileVal');
    exit(1);
  }

  // Verify running inside git repository
  if (!await _isGitRepository()) {
    stderr.writeln('Error: Not inside a git repository.');
    exit(1);
  }

  final gitRoot = await _getGitRoot();
  final relativeBenchmarkPath = p.relative(
    benchmarkFile.absolute.path,
    from: gitRoot,
  );

  Directory? worktreeDir1;
  Directory? worktreeDir2;

  try {
    print('Creating worktree for $ref1...');
    worktreeDir1 = Directory.systemTemp.createTempSync('criterion_git_ref1_');
    await _createWorktree(worktreeDir1.path, ref1);

    print('Creating worktree for $ref2...');
    worktreeDir2 = Directory.systemTemp.createTempSync('criterion_git_ref2_');
    await _createWorktree(worktreeDir2.path, ref2);

    final results1 = await _runBenchmarkInWorktree(
      worktreeDir1.path,
      relativeBenchmarkPath,
      benchmarkFile,
      extraArgs,
    );

    final results2 = await _runBenchmarkInWorktree(
      worktreeDir2.path,
      relativeBenchmarkPath,
      benchmarkFile,
      extraArgs,
    );

    final report = compareResults(results1, results2).toMarkdownTable();
    print(report);
  } catch (e, stackTrace) {
    stderr.writeln('Error: $e');
    stderr.writeln(stackTrace);
    exit(1);
  } finally {
    if (worktreeDir1 != null) {
      await _cleanupWorktree(worktreeDir1.path);
    }
    if (worktreeDir2 != null) {
      await _cleanupWorktree(worktreeDir2.path);
    }
  }
}

Future<bool> _isGitRepository() async {
  try {
    final result = await Process.run('git', [
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    return result.exitCode == 0 && result.stdout.toString().trim() == 'true';
  } catch (_) {
    return false;
  }
}

Future<String> _getGitRoot() async {
  final result = await Process.run('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) {
    throw Exception('Failed to find git root: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

Future<void> _createWorktree(String path, String ref) async {
  final result = await Process.run('git', [
    'worktree',
    'add',
    '--detach',
    path,
    ref,
  ]);
  if (result.exitCode != 0) {
    throw Exception('Failed to create worktree for $ref: ${result.stderr}');
  }
}

Future<void> _cleanupWorktree(String path) async {
  print('Cleaning up worktree at $path...');
  final result = await Process.run('git', [
    'worktree',
    'remove',
    '--force',
    path,
  ]);
  if (result.exitCode != 0) {
    stderr.writeln(
      'Warning: Failed to remove worktree $path: ${result.stderr}',
    );
  }
  final dir = Directory(path);
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (e) {
      stderr.writeln('Warning: Failed to delete temp directory $path: $e');
    }
  }
}

Future<List<BenchmarkResult>> _runBenchmarkInWorktree(
  String worktreePath,
  String relativeBenchmarkPath,
  File sourceBenchmarkFile,
  List<String> extraArgs,
) async {
  final targetBenchmarkPath = p.join(worktreePath, relativeBenchmarkPath);
  final targetBenchmarkFile = File(targetBenchmarkPath);

  // Ensure parent directories exist
  targetBenchmarkFile.parent.createSync(recursive: true);

  // Copy benchmark file
  sourceBenchmarkFile.copySync(targetBenchmarkPath);

  final dartExe = Platform.resolvedExecutable;

  print('Running pub get in $worktreePath...');
  final pubGetResult = await Process.run(dartExe, [
    'pub',
    'get',
  ], workingDirectory: worktreePath);
  if (pubGetResult.exitCode != 0) {
    throw Exception(
      'pub get failed in $worktreePath:\nStdout: ${pubGetResult.stdout}\nStderr: ${pubGetResult.stderr}',
    );
  }

  print('Running benchmark in $worktreePath...');
  final runResult = await Process.run(dartExe, [
    'run',
    'bin/run.dart',
    relativeBenchmarkPath,
    ...extraArgs,
  ], workingDirectory: worktreePath);

  if (runResult.exitCode != 0) {
    throw Exception(
      'Benchmark run failed in $worktreePath:\nStdout: ${runResult.stdout}\nStderr: ${runResult.stderr}',
    );
  }

  final resultsPath = p.join(worktreePath, 'benchmark/report/results.json');
  final resultsFile = File(resultsPath);
  if (!resultsFile.existsSync()) {
    throw Exception('Results file not found at $resultsPath');
  }

  final jsonContent = resultsFile.readAsStringSync();
  final List<dynamic> jsonList = jsonDecode(jsonContent);
  return jsonList
      .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
      .toList();
}
