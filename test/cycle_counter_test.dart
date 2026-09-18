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

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:criterion/src/cycle_counter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasCCompiler {
  final compiler = Platform.isMacOS ? 'clang' : 'gcc';
  try {
    final result = Process.runSync(compiler, ['--version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

bool get _isSupportedPlatformAndArch {
  final isLinuxOrMac = Platform.isLinux || Platform.isMacOS;
  final isSupportedArch =
      Abi.current() == Abi.linuxX64 ||
      Abi.current() == Abi.linuxArm64 ||
      Abi.current() == Abi.macosX64 ||
      Abi.current() == Abi.macosArm64;
  return isLinuxOrMac && isSupportedArch;
}

void main() {
  test('CycleCounter measures cycles if supported', () async {
    final config = CriterionConfig(
      generateHtmlReport: false,
      exportJson: false,
      useKbssd: false,
      measureCycles: true,
    );

    final prints = <String>[];
    final results = await runZoned(
      () => criterion('Cycle Test', (c) {
        c.bench(
          'simple-loop',
          () {
            var x = 0;
            for (var i = 0; i < 1000; i++) {
              x += i;
            }
            if (x == 0) throw StateError('invalid x');
          },
          samples: 5,
          warmupDuration: Duration.zero,
        );
      }, config: config),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          prints.add(line);
          parent.print(zone, line);
        },
      ),
    );

    expect(results.length, equals(1));
    final result = results.first;

    final hasCyclesPrint = prints.any((p) => p.contains('cycles:'));
    final cycles = result.primary.cyclesPerIteration;

    if (_isSupportedPlatformAndArch && _hasCCompiler) {
      expect(CycleCounter.isSupported, isTrue);
      expect(cycles, isNotNull);
      expect(cycles!, greaterThan(0));
      expect(hasCyclesPrint, isTrue);
      print('Cycles measured: $cycles');
    } else if (cycles != null) {
      expect(cycles, greaterThan(0));
      expect(hasCyclesPrint, isTrue);
      print('Cycles measured: $cycles');
    } else {
      print('Cycle counting not supported on this platform.');
      expect(hasCyclesPrint, isFalse);
    }
  });

  test('CycleCounter.measure works directly', () async {
    final cycles = await CycleCounter.measure(
      fn: () {
        var x = 0;
        for (var i = 0; i < 1000; i++) {
          x += i;
        }
        if (x == 0) throw StateError('invalid x');
      },
      iterations: 100,
    );

    if (_isSupportedPlatformAndArch && _hasCCompiler) {
      expect(CycleCounter.isSupported, isTrue);
      expect(cycles, isNotNull);
      expect(cycles!, greaterThan(0));
    } else if (CycleCounter.isSupported) {
      expect(cycles, isNotNull);
      expect(cycles!, greaterThan(0));
    } else {
      expect(cycles, isNull);
    }
  });

  test('CycleCounter works when compiled to AOT', () async {
    final tempDir = Directory.systemTemp.createTempSync('criterion_aot_test_');
    try {
      final scriptFile = File(p.join(tempDir.path, 'aot_test.dart'));
      final exeFile = File(p.join(tempDir.path, 'aot_test.exe'));
      await scriptFile.writeAsString('''
import 'dart:io';
import 'package:criterion/src/cycle_counter.dart';

void main() async {
  final cycles = await CycleCounter.measure(
    fn: () {
      var x = 0;
      for (var i = 0; i < 1000; i++) {
        x += i;
      }
      if (x == 0) throw StateError('invalid x');
    },
    iterations: 100,
  );
  if (CycleCounter.isSupported) {
    if (cycles != null && cycles > 0) {
      print('CYCLES: \$cycles');
      exit(0);
    } else {
      print('MEASURE_FAILED');
      exit(1);
    }
  } else {
    print('UNSUPPORTED');
    exit(0);
  }
}
''');

      final packageConfigFile = File(
        p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
      );

      final compileResult = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        '--packages=${packageConfigFile.absolute.path}',
        scriptFile.path,
        '-o',
        exeFile.path,
      ]);

      expect(
        compileResult.exitCode,
        equals(0),
        reason:
            'AOT compile failed: ${compileResult.stderr}\n${compileResult.stdout}',
      );

      // Run from tempDir so it's outside package directory
      final runResult = await Process.run(
        exeFile.path,
        [],
        workingDirectory: tempDir.path,
      );
      expect(
        runResult.exitCode,
        equals(0),
        reason:
            'AOT execution failed: ${runResult.stderr}\n${runResult.stdout}',
      );

      if (_isSupportedPlatformAndArch && _hasCCompiler) {
        expect(runResult.stdout, contains('CYCLES:'));
      }
    } finally {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('Concurrent CycleCounter.init() calls do not race', () async {
    await Future.wait([
      CycleCounter.init(),
      CycleCounter.init(),
      CycleCounter.init(),
    ]);
    expect(CycleCounter.isSupported, isA<bool>());
  });
}
