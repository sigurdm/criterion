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

import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/run.dart <benchmark_file.dart> [extra_args...]');
    exit(1);
  }

  final targetFile = File(args.first);
  if (!targetFile.existsSync()) {
    print('Error: Target file does not exist: ${targetFile.path}');
    exit(1);
  }

  final extraArgs = args.sublist(1);

  final targetPath = targetFile.absolute.path;
  var tempExePath = targetPath;
  if (tempExePath.endsWith('.dart')) {
    tempExePath = '${tempExePath.substring(0, tempExePath.length - 5)}_aot.exe';
  } else {
    tempExePath = '${tempExePath}_aot.exe';
  }

  print('Compiling $targetPath to AOT binary...');
  final dartPath = Platform.resolvedExecutable;

  final compileResult = await Process.run(dartPath, [
    'compile',
    'exe',
    targetPath,
    '-o',
    tempExePath,
  ]);

  if (compileResult.exitCode != 0) {
    print('Compilation failed with exit code ${compileResult.exitCode}');
    print(compileResult.stdout);
    print(compileResult.stderr);
    exit(compileResult.exitCode);
  }

  print('Executing compiled binary: $tempExePath');
  final process = await Process.start(
    tempExePath,
    extraArgs,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;

  // Cleanup
  try {
    final tempExeFile = File(tempExePath);
    if (tempExeFile.existsSync()) {
      tempExeFile.deleteSync();
    }
  } catch (e) {
    print('Warning: Failed to delete temporary binary $tempExePath: $e');
  }

  exit(exitCode);
}
