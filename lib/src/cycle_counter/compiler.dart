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
import 'dart:isolate';
import 'package:path/path.dart' as p;

/// Compiles the cycle counter C helper to a shared library.
final class CycleCounterCompiler {
  /// Compiles `cycle_counter.c` and returns the path to the library.
  ///
  /// Returns `null` if compilation fails or is unsupported.
  static Future<String?> compile() async {
    try {
      final packageUri = Uri.parse(
        'package:criterion/src/cycle_counter/cycle_counter.c',
      );
      final fileUri = await Isolate.resolvePackageUri(packageUri);
      if (fileUri == null) {
        stderr.writeln(
          'Warning: Could not resolve package URI for cycle_counter.c',
        );
        return null;
      }
      final cFilePath = File.fromUri(fileUri).path;

      final outputDir = Directory('.dart_tool/criterion');
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      String libName;
      List<String> args;
      String compiler = 'gcc';

      if (Platform.isLinux) {
        libName = 'libcycle_counter.so';
        args = [
          '-O3',
          '-shared',
          '-fPIC',
          cFilePath,
          '-o',
          p.join(outputDir.path, libName),
        ];
      } else if (Platform.isMacOS) {
        libName = 'libcycle_counter.dylib';
        compiler = 'clang';
        args = [
          '-O3',
          '-shared',
          '-undefined',
          'dynamic_lookup',
          cFilePath,
          '-o',
          p.join(outputDir.path, libName),
        ];
      } else if (Platform.isWindows) {
        libName = 'cycle_counter.dll';
        // Try gcc (MinGW) on Windows
        args = [
          '-O3',
          '-shared',
          cFilePath,
          '-o',
          p.join(outputDir.path, libName),
        ];
      } else {
        return null;
      }

      final result = await Process.run(compiler, args);
      if (result.exitCode != 0) {
        stderr.writeln(
          'Warning: Failed to compile cycle_counter.c:\n${result.stderr}',
        );
        return null;
      }

      return p.absolute(p.join(outputDir.path, libName));
    } catch (e) {
      stderr.writeln('Warning: Error compiling cycle_counter.c: $e');
      return null;
    }
  }
}
