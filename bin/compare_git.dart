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

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:args/args.dart';
import 'package:criterion/criterion.dart';

void main(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addOption(
      'noise-threshold',
      defaultsTo: '0.01',
      help:
          'Relative noise threshold for regression detection (e.g. 0.01 for 1%).',
    )
    ..addFlag(
      'fail-on-regression',
      defaultsTo: false,
      negatable: false,
      help: 'Exit with non-zero exit code if a regression is detected.',
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln(e);
    stderr.writeln(
      'Usage: dart run criterion:compare_git [options] <ref1> <ref2> <benchmark_file.dart> [extra_args...]',
    );
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (parsed.rest.length < 3) {
    stderr.writeln(
      'Usage: dart run criterion:compare_git [options] <ref1> <ref2> <benchmark_file.dart> [extra_args...]',
    );
    stderr.writeln(parser.usage);
    exit(1);
  }

  final noiseThreshold = double.tryParse(parsed['noise-threshold'] as String);
  if (noiseThreshold == null || noiseThreshold < 0) {
    stderr.writeln(
      "Error: Invalid --noise-threshold value: ${parsed['noise-threshold']}",
    );
    exit(1);
  }
  final failOnRegression = parsed['fail-on-regression'] as bool;

  final ref1 = parsed.rest[0];
  final ref2 = parsed.rest[1];
  final benchmarkFileVal = parsed.rest[2];
  final extraArgs = parsed.rest.sublist(3);

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
  final packageRoot = _findPackageRoot(benchmarkFile, gitRoot);
  final relPackageDir = p.relative(packageRoot, from: gitRoot);

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
      relPackageDir,
    );

    final results2 = await _runBenchmarkInWorktree(
      worktreeDir2.path,
      relativeBenchmarkPath,
      benchmarkFile,
      extraArgs,
      relPackageDir,
    );

    final comparison = compareResults(
      results1,
      results2,
      noiseThreshold: noiseThreshold,
    );
    print(comparison.toMarkdownTable());

    if (failOnRegression && comparison.regressions.isNotEmpty) {
      stderr.writeln(
        'Error: Regressions detected in ${comparison.regressions.length} benchmark(s).',
      );
      exitCode = 1;
    }
  } catch (e, stackTrace) {
    stderr.writeln('Error: $e');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    if (worktreeDir1 != null) {
      await _cleanupWorktree(worktreeDir1.path);
    }
    if (worktreeDir2 != null) {
      await _cleanupWorktree(worktreeDir2.path);
    }
  }
}

String _findPackageRoot(File benchmarkFile, String gitRoot) {
  Directory dir = benchmarkFile.existsSync()
      ? benchmarkFile.parent.absolute
      : Directory.current.absolute;
  final root = Directory(gitRoot).absolute;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    if (p.equals(dir.path, root.path) || p.equals(dir.path, dir.parent.path)) {
      break;
    }
    dir = dir.parent;
  }
  return gitRoot;
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
  String relPackageDir,
) async {
  final targetBenchmarkPath = p.join(worktreePath, relativeBenchmarkPath);
  final targetBenchmarkFile = File(targetBenchmarkPath);

  // Ensure parent directories exist
  targetBenchmarkFile.parent.createSync(recursive: true);

  // Copy benchmark file
  sourceBenchmarkFile.copySync(targetBenchmarkPath);

  final dartExe = Platform.resolvedExecutable;
  final worktreePackageDir = relPackageDir == '.'
      ? worktreePath
      : p.join(worktreePath, relPackageDir);

  print('Running pub get in $worktreePackageDir...');
  final pubGetResult = await Process.run(dartExe, [
    'pub',
    'get',
  ], workingDirectory: worktreePackageDir);
  if (pubGetResult.exitCode != 0) {
    throw Exception(
      'pub get failed in $worktreePackageDir:\nStdout: ${pubGetResult.stdout}\nStderr: ${pubGetResult.stderr}',
    );
  }

  print('Running benchmark in $worktreePackageDir...');
  final benchmarkArg = p.relative(
    targetBenchmarkPath,
    from: worktreePackageDir,
  );
  final runResult = await Process.run(dartExe, [
    'run',
    'criterion:run',
    '--json',
    benchmarkArg,
    ...extraArgs,
  ], workingDirectory: worktreePackageDir);

  if (runResult.exitCode != 0) {
    throw Exception(
      'Benchmark run failed in $worktreePackageDir:\nStdout: ${runResult.stdout}\nStderr: ${runResult.stderr}',
    );
  }

  final allResults = <BenchmarkResult>[];
  final stdoutString = runResult.stdout.toString();
  for (final line in stdoutString.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is List &&
            parsed.every(
              (e) =>
                  e is Map<String, dynamic> &&
                  e.containsKey('name') &&
                  e.containsKey('primary'),
            )) {
          allResults.addAll(loadResults(trimmed));
        }
      } catch (_) {
        // Not a valid JSON array of benchmark results, continue
      }
    }
  }

  if (allResults.isEmpty) {
    throw Exception(
      'No benchmark results found in stdout in $worktreePackageDir.\nStdout: ${runResult.stdout}\nStderr: ${runResult.stderr}',
    );
  }

  return allResults;
}
