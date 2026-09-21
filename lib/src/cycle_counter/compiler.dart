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

import 'dart:ffi' show Abi;
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

#if defined(_WIN32)
#define CRITERION_EXPORT __declspec(dllexport)
#else
#define CRITERION_EXPORT __attribute__((visibility("default")))
#endif

CRITERION_EXPORT uint64_t get_cycles(void);

#if defined(__x86_64__) || defined(_M_X64)
#ifdef _MSC_VER
#include <intrin.h>
#else
#include <x86intrin.h>
#endif

CRITERION_EXPORT uint64_t get_cycles(void) {
    unsigned int aux;
    return __rdtscp(&aux);
}
#elif defined(__aarch64__)
CRITERION_EXPORT uint64_t get_cycles(void) {
    uint64_t val;
    // Read virtual timer counter. It runs at a fixed frequency (usually 1-50MHz),
    // NOT CPU clock speed, but it is high resolution and accessible from user space.
    asm volatile("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}
#elif defined(_M_ARM64)
#include <intrin.h>

CRITERION_EXPORT uint64_t get_cycles(void) {
    // ARM64_CNTVCT = _ARM64_SYSREG(3, 3, 14, 0, 2)
    return (uint64_t)_ReadStatusReg(_ARM64_SYSREG(3, 3, 14, 0, 2));
}
#else
CRITERION_EXPORT uint64_t get_cycles(void) {
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
      final abiTag = Abi.current().toString().replaceAll('.', '_');
      final String libName;
      final String compiler;

      if (Platform.isLinux) {
        libName = 'libcycle_counter_$abiTag.so';
        compiler = 'gcc';
      } else if (Platform.isMacOS) {
        libName = 'libcycle_counter_$abiTag.dylib';
        compiler = 'clang';
      } else if (Platform.isWindows) {
        libName = 'cycle_counter_$abiTag.dll';
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
      Directory? tempDir;
      try {
        final packageUri = Uri.parse(
          'package:criterion/src/cycle_counter/cycle_counter.c',
        );
        final fileUri = await Isolate.resolvePackageUri(packageUri);
        if (fileUri != null && File.fromUri(fileUri).existsSync()) {
          cFilePath = File.fromUri(fileUri).path;
        } else {
          tempDir = Directory.systemTemp.createTempSync('criterion_cycle_');
          final tempCFile = File(p.join(tempDir.path, 'cycle_counter.c'));
          tempCFile.writeAsStringSync(_cSource);
          cFilePath = tempCFile.path;
        }
      } catch (_) {
        tempDir = Directory.systemTemp.createTempSync('criterion_cycle_');
        final tempCFile = File(p.join(tempDir.path, 'cycle_counter.c'));
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
        if (tempDir != null && tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      stderr.writeln('Warning: Error compiling cycle_counter.c: $e');
      return null;
    }
  }
}
