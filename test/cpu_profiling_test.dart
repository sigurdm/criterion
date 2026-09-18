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
import 'dart:convert';
import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:criterion/src/cpu_profiler.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('criterion_cpu_profile_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'CPU profiling collects samples, reports top functions, and exports JSON',
    () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: false,
        useKbssd: false,
        cpuProfiling: true,
      );

      final prints = <String>[];
      final results = await runZoned(
        () => criterion('CPU Profile Test', (c) {
          c.bench(
            'fib-cpu',
            () {
              final r = fib(20);
              if (r == 0) throw StateError('invalid fib');
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
      expect(result.primary.cpuProfile, isNotNull);
      final profile = result.primary.cpuProfile!;
      expect(profile.sampleCount, greaterThan(0));

      final hasFib = profile.functions.any(
        (f) => f.name.contains('fib') && f.exclusiveTicks > 0,
      );
      expect(
        hasFib,
        isTrue,
        reason: 'Expected fib in CPU profile: ${profile.functions}',
      );

      final hasTopCpuPrint = prints.any(
        (p) => p.contains('Top CPU functions:'),
      );
      expect(hasTopCpuPrint, isTrue);
      final hasFibPrint = prints.any((p) => p.contains('fib'));
      expect(hasFibPrint, isTrue);

      // Verify exported file
      final expectedFilePath = p.join(
        tempDir.path,
        'profiles',
        'fib-cpu.cpuprofile.json',
      );
      final exportedFile = File(expectedFilePath);
      expect(
        exportedFile.existsSync(),
        isTrue,
        reason: 'Expected profile file to exist at $expectedFilePath',
      );

      final fileContent = exportedFile.readAsStringSync();
      final decoded = jsonDecode(fileContent) as Map<String, dynamic>;
      expect(decoded['type'], equals('CpuSamples'));
      expect(decoded['samples'], isList);
      expect(decoded['functions'], isList);
    },
  );

  test('CPU profile is reported when memory measurement is disabled', () async {
    // Regression test: `_printCpuProfile` used to be nested inside the memory
    // reporting block, so `cpuProfiling: true` combined with
    // `measureMemory: false` (or `--no-memory` / `--timing-only`, or any host
    // where the allocation profile comes back null) printed nothing at all.
    final config = CriterionConfig(
      reportDir: tempDir.path,
      generateHtmlReport: false,
      exportJson: false,
      exportHistory: false,
      useKbssd: false,
      cpuProfiling: true,
      measureMemory: false,
      measureInstructions: false,
      measureCycles: false,
    );

    final prints = <String>[];
    await runZoned(
      () => criterion('CPU Profile Without Memory', (c) {
        c.bench(
          'fib-cpu-no-memory',
          () {
            final r = fib(20);
            if (r == 0) throw StateError('invalid fib');
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

    expect(
      prints.any((p) => p.contains('memory:')),
      isFalse,
      reason: 'memory measurement was disabled',
    );
    expect(
      prints.any((p) => p.contains('Top CPU functions:')),
      isTrue,
      reason: 'CPU profile should be printed independently of memory: $prints',
    );
  });

  test('CpuProfiler.collect supports setup callback', () async {
    var setupCount = 0;
    final profile = await CpuProfiler.collect(
      fn: (List<int> list) {
        list.sort();
      },
      iterations: 100,
      setup: () {
        setupCount++;
        return [5, 3, 1, 4, 2];
      },
      batchSize: BatchSize.numIterations(20),
    );
    expect(profile, isNotNull);
    expect(setupCount, equals(100));
  });
}
