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
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Criterion API', () {
    test('registers benchmarks and groups correctly', () {
      final c = Criterion();
      c.bench('simple', () {});
      c.group('my group', () {
        c.bench('nested 1', () {});
        c.group('subgroup', () {
          c.bench('nested 2', () {});
        });
      });

      expect(c.benchmarks.length, equals(3));
      expect(c.benchmarks[0].name, equals('simple'));
      expect(c.benchmarks[1].name, equals('my group / nested 1'));
      expect(c.benchmarks[2].name, equals('my group / subgroup / nested 2'));
    });

    test(
      'executes benchmark lifecycle: warmup, calibration, sampling',
      () async {
        var callCount = 0;
        final c = Criterion();

        // We use very small values to make tests run fast
        c.bench(
          'mock bench',
          () => callCount++,
          samples: 10,
          warmupDuration: const Duration(milliseconds: 5),
        );

        await c.run();

        // Ensure the benchmark was actually called multiple times
        // during warmup, calibration, and 10 samples.
        expect(callCount, greaterThan(15));
      },
    );

    test('executes benchmark with noOp calibration', () async {
      final printLines = <String>[];
      await runZonedGuarded(
        () async {
          final c = Criterion();
          c.bench(
            'ffi-mock',
            () {
              // Simulate some logic
              var sum = 0;
              for (var i = 0; i < 1000; i++) {
                sum += i;
              }
              if (sum == 0) throw StateError('invalid sum');
            },
            noOp: () {
              // Simulate no-op overhead
            },
            samples: 5,
            warmupDuration: const Duration(milliseconds: 5),
          );
          await c.run();
        },
        (error, stack) {
          fail('Run failed with error: $error\n$stack');
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printLines.add(line);
            parent.print(zone, line);
          },
        ),
      );

      // Verify that the output formats with [Total: ...] [Overhead (FFI bridge): ...] [Net logic: ...]
      final timeLine = printLines.firstWhere(
        (line) => line.contains('time:'),
        orElse: () => '',
      );
      expect(timeLine, isNotEmpty);
      expect(timeLine, contains('Total:'));
      expect(timeLine, contains('Overhead (FFI bridge):'));
      expect(timeLine, contains('Net logic:'));
    });
  });
}
