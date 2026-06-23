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
import 'package:args/args.dart';
import 'package:criterion/src/dart_environment.dart' as env_helpers;
import 'package:node_preamble/preamble.dart' as node_preamble;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addMultiOption(
      'flavor',
      abbr: 'f',
      allowed: ['jit', 'aot', 'js', 'wasm'],
      defaultsTo: ['aot'],
      help: 'The flavor(s) to run the benchmark in.',
    )
    ..addFlag('json', help: 'Output aggregated JSON results to stdout.')
    ..addMultiOption('compiler-flag', help: 'Extra compiler flags.')
    ..addMultiOption('vm-flag', help: 'Extra VM/Node flags.');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print(e);
    print(parser.usage);
    exit(1);
  }

  if (results.rest.isEmpty) {
    print('Usage: dart run criterion:run [options] <benchmark_file.dart>');
    print(parser.usage);
    exit(1);
  }

  final targetPath = results.rest.first;
  final targetFile = File(targetPath);
  if (!targetFile.existsSync()) {
    print('Error: Target file does not exist: $targetPath');
    exit(1);
  }

  final flavors = results['flavor'] as List<String>;
  final isJson = results['json'] as bool;
  final compilerFlags = results['compiler-flag'] as List<String>;
  final vmFlags = results['vm-flag'] as List<String>;

  final dartPath = Platform.resolvedExecutable;
  final os = Platform.operatingSystem;
  final sdkVersion = Platform.version.split(' ').first;

  final tempDir = Directory.systemTemp.createTempSync('criterion_run_');

  final aggregatedJsonResults = <dynamic>[];

  try {
    for (final flavor in flavors) {
      if (!isJson) {
        print('=== Running flavor: $flavor ===');
      }

      final defines = env_helpers.dartDefineFlags(
        platform: flavor,
        os: os,
        dartSdkVersion: sdkVersion,
        json: isJson,
      );

      final defineFlags = defines;

      if (flavor == 'jit') {
        final processArgs = [...vmFlags, ...defineFlags, targetPath];
        await _runProcess(dartPath, processArgs, isJson, aggregatedJsonResults);
      } else if (flavor == 'aot') {
        final tempExePath = '${tempDir.path}/temp_aot.exe';
        if (!isJson) {
          print('Compiling to AOT...');
        }
        final compileArgs = [
          'compile',
          'exe',
          ...compilerFlags,
          ...defineFlags,
          targetPath,
          '-o',
          tempExePath,
        ];
        final compileResult = await Process.run(dartPath, compileArgs);
        if (compileResult.exitCode != 0) {
          _printCompileError(compileResult);
          exit(compileResult.exitCode);
        }
        await _runProcess(tempExePath, [], isJson, aggregatedJsonResults);
      } else if (flavor == 'js') {
        final tempJsPath = '${tempDir.path}/temp_js.js';
        if (!isJson) {
          print('Compiling to JS...');
        }
        final compileArgs = [
          'compile',
          'js',
          ...compilerFlags,
          ...defineFlags,
          targetPath,
          '-o',
          tempJsPath,
        ];
        final compileResult = await Process.run(dartPath, compileArgs);
        if (compileResult.exitCode != 0) {
          _printCompileError(compileResult);
          exit(compileResult.exitCode);
        }

        // Prepend preamble
        final jsFile = File(tempJsPath);
        final jsContent = jsFile.readAsStringSync();
        final preamble = node_preamble.getPreamble();
        jsFile.writeAsStringSync('$preamble\n$jsContent');

        await _runProcess(
          'node',
          [...vmFlags, tempJsPath],
          isJson,
          aggregatedJsonResults,
        );
      } else if (flavor == 'wasm') {
        final tempWasmPath = '${tempDir.path}/temp_wasm.wasm';
        final tempMjsPath = '${tempDir.path}/temp_wasm.mjs';
        final tempRunnerPath = '${tempDir.path}/temp_wasm_runner.mjs';

        if (!isJson) {
          print('Compiling to WASM...');
        }
        final compileArgs = [
          'compile',
          'wasm',
          ...compilerFlags,
          ...defineFlags,
          targetPath,
          '-o',
          tempWasmPath,
        ];
        final compileResult = await Process.run(dartPath, compileArgs);
        if (compileResult.exitCode != 0) {
          _printCompileError(compileResult);
          exit(compileResult.exitCode);
        }

        // Create the WASM runner script
        final runnerContent =
            '''
import { compile } from 'file://$tempMjsPath';
import { readFileSync } from 'fs';
import { argv } from 'process';

const bytes = readFileSync('$tempWasmPath');
const compiled = await compile(bytes);
const instance = await compiled.instantiate();
const dartArgs = argv.slice(2);
instance.invokeMain(...dartArgs);
''';
        File(tempRunnerPath).writeAsStringSync(runnerContent);

        await _runProcess(
          'node',
          [...vmFlags, tempRunnerPath],
          isJson,
          aggregatedJsonResults,
        );
      }
    }

    if (isJson) {
      print(jsonEncode(aggregatedJsonResults));
    }
  } finally {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (e) {
      if (!isJson) {
        print('Warning: Failed to clean up temp directory ${tempDir.path}: $e');
      }
    }
  }
}

void _printCompileError(ProcessResult result) {
  print('Compilation failed:');
  print(result.stdout);
  print(result.stderr);
}

Future<void> _runProcess(
  String executable,
  List<String> arguments,
  bool isJson,
  List<dynamic> aggregatedResults,
) async {
  if (isJson) {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      print('Execution failed with exit code ${result.exitCode}');
      print(result.stdout);
      print(result.stderr);
      exit(result.exitCode);
    }
    try {
      final lines = (result.stdout as String).split('\n');
      dynamic parsed;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          try {
            parsed = jsonDecode(trimmed);
            break;
          } catch (_) {
            // Not valid JSON, continue
          }
        }
      }
      if (parsed == null) {
        throw FormatException('Could not find JSON array in output');
      }
      if (parsed is List) {
        aggregatedResults.addAll(parsed);
      } else {
        aggregatedResults.add(parsed);
      }
    } catch (e) {
      print('Failed to parse JSON output from process: $e');
      print('Output was:');
      print(result.stdout);
      exit(1);
    }
  } else {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      exit(exitCode);
    }
  }
}
