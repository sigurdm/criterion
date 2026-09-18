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

const String _cSource = r'''
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

#include <stdint.h>

#if defined(__x86_64__) || defined(_M_X64)
#ifdef _MSC_VER
#include <intrin.h>
#else
#include <x86intrin.h>
#endif

uint64_t get_cycles() {
    return __rdtsc();
}
#elif defined(__aarch64__)
uint64_t get_cycles() {
    uint64_t val;
    // Read virtual timer counter. It runs at a fixed frequency (usually 1-50MHz),
    // NOT CPU clock speed, but it is high resolution and accessible from user space.
    asm volatile("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}
#else
uint64_t get_cycles() {
    return 0; // Unsupported
}
#endif
''';

/// Compiles the cycle counter C helper to a shared library.
final class CycleCounterCompiler {
  /// Compiles `cycle_counter.c` and returns the path to the library.
  ///
  /// Returns `null` if compilation fails or is unsupported.
  static Future<String?> compile() async {
    try {
      final String libName;
      final String compiler;

      if (Platform.isLinux) {
        libName = 'libcycle_counter.so';
        compiler = 'gcc';
      } else if (Platform.isMacOS) {
        libName = 'libcycle_counter.dylib';
        compiler = 'clang';
      } else if (Platform.isWindows) {
        libName = 'cycle_counter.dll';
        compiler = 'gcc';
      } else {
        return null;
      }

      final outputDir = Directory('.dart_tool/criterion');
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      final targetLib = File(p.join(outputDir.path, libName));
      if (targetLib.existsSync() && targetLib.lengthSync() > 0) {
        return targetLib.absolute.path;
      }

      String cFilePath;
      File? tempCFile;
      try {
        final packageUri = Uri.parse(
          'package:criterion/src/cycle_counter/cycle_counter.c',
        );
        final fileUri = await Isolate.resolvePackageUri(packageUri);
        if (fileUri != null && File.fromUri(fileUri).existsSync()) {
          cFilePath = File.fromUri(fileUri).path;
        } else {
          tempCFile = File(
            p.join(Directory.systemTemp.path, 'cycle_counter_$pid.c'),
          );
          tempCFile.writeAsStringSync(_cSource);
          cFilePath = tempCFile.path;
        }
      } catch (_) {
        tempCFile = File(
          p.join(Directory.systemTemp.path, 'cycle_counter_$pid.c'),
        );
        tempCFile.writeAsStringSync(_cSource);
        cFilePath = tempCFile.path;
      }

      final ext = p.extension(libName);
      final base = p.basenameWithoutExtension(libName);
      final tempLibName = '${base}_$pid$ext';
      final tempLibPath = p.join(outputDir.path, tempLibName);

      final List<String> args;
      if (Platform.isLinux) {
        args = ['-O3', '-shared', '-fPIC', cFilePath, '-o', tempLibPath];
      } else if (Platform.isMacOS) {
        args = [
          '-O3',
          '-shared',
          '-undefined',
          'dynamic_lookup',
          cFilePath,
          '-o',
          tempLibPath,
        ];
      } else if (Platform.isWindows) {
        args = ['-O3', '-shared', cFilePath, '-o', tempLibPath];
      } else {
        return null;
      }

      try {
        final result = await Process.run(compiler, args);
        if (result.exitCode != 0) {
          stderr.writeln(
            'Warning: Failed to compile cycle_counter.c:\n${result.stderr}',
          );
          return null;
        }

        final tempLibFile = File(tempLibPath);
        if (!tempLibFile.existsSync() || tempLibFile.lengthSync() == 0) {
          return null;
        }

        if (targetLib.existsSync() && targetLib.lengthSync() > 0) {
          try {
            tempLibFile.deleteSync();
          } catch (_) {}
          return targetLib.absolute.path;
        }

        try {
          tempLibFile.renameSync(targetLib.path);
        } catch (_) {
          if (targetLib.existsSync() && targetLib.lengthSync() > 0) {
            try {
              tempLibFile.deleteSync();
            } catch (_) {}
            return targetLib.absolute.path;
          }
          rethrow;
        }

        return targetLib.absolute.path;
      } finally {
        if (tempCFile != null && tempCFile.existsSync()) {
          try {
            tempCFile.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      stderr.writeln('Warning: Error compiling cycle_counter.c: $e');
      return null;
    }
  }
}
