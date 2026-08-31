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

    group('Batched Setups and BatchSize', () {
      test('default batchSize is smallInput when setup is provided', () {
        final c = Criterion();
        c.bench<int>('with setup', (val) => val + 1, setup: () => 42);
        expect(c.benchmarks.first.batchSize, equals(BatchSize.smallInput));
      });

      test('default batchSize is unbatched when setup is omitted', () {
        final c = Criterion();
        c.bench('no setup', () => 1 + 1);
        expect(c.benchmarks.first.batchSize, equals(BatchSize.unbatched));
      });

      test('throws ArgumentError if batchSize is passed without setup', () {
        final c = Criterion();
        expect(
          () => c.bench(
            'invalid batchSize',
            () {},
            batchSize: BatchSize.smallInput,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => c.variants('invalid variants batchSize', {
            'v1': () {},
          }, batchSize: BatchSize.largeInput),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => c.benchWith<dynamic, int>(
            'invalid benchWith batchSize',
            [1, 2],
            (val) {},
            batchSize: BatchSize.numIterations(10),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        'BatchSize.numIterations throws ArgumentError on non-positive n',
        () {
          expect(
            () => BatchSize.numIterations(0),
            throwsA(isA<ArgumentError>()),
          );
          expect(
            () => BatchSize.numIterations(-5),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test('batchSizeFor calculates batch sizes accurately', () {
        expect(BatchSize.smallInput.batchSizeFor(2500), equals(1000));
        expect(BatchSize.smallInput.batchSizeFor(250), equals(250));
        expect(BatchSize.smallInput.batchSizeFor(50), equals(50));
        expect(BatchSize.largeInput.batchSizeFor(10), equals(1));
        expect(BatchSize.unbatched.batchSizeFor(1234), equals(1234));
        final custom = BatchSize.numIterations(25);
        expect(custom.batchSizeFor(60), equals(25));
        expect(custom.batchSizeFor(15), equals(15));
      });

      test('executes batched setup benchmark cleanly', () async {
        var setupCount = 0;
        var runCount = 0;
        final c = Criterion(
          config: const CriterionConfig(
            useKbssd: false,
            generateHtmlReport: false,
            exportJson: false,
          ),
        );

        c.bench<List<int>>(
          'batched sort',
          (list) {
            runCount++;
            list.sort();
          },
          setup: () {
            setupCount++;
            return [3, 1, 2];
          },
          batchSize: BatchSize.numIterations(100),
          samples: 5,
          warmupDuration: const Duration(milliseconds: 2),
        );

        final results = await c.run();
        expect(results, hasLength(1));
        expect(setupCount, equals(runCount));
        expect(runCount, greaterThan(10));
      });
    });

    group('Function signature and setup validation', () {
      test('bench throws ArgumentError on signature mismatch', () {
        final c = Criterion();
        // setup provided, but fn takes 0 args
        expect(
          () => c.bench('test', () {}, setup: () => 42),
          throwsArgumentError,
        );
        // setup provided, but noOp takes 0 args
        expect(
          () => c.bench('test', (x) {}, setup: () => 42, noOp: () {}),
          throwsArgumentError,
        );
        // setup omitted, but fn takes 1 arg
        expect(() => c.bench('test', (x) {}), throwsArgumentError);
        // setup omitted, but noOp takes 1 arg
        expect(() => c.bench('test', () {}, noOp: (x) {}), throwsArgumentError);
      });

      test('variants throws ArgumentError on signature mismatch', () {
        final c = Criterion();
        // setup provided, but variant takes 0 args
        expect(
          () => c.variants('v', {'v1': () {}}, setup: () => 42),
          throwsArgumentError,
        );
        // setup omitted, but variant takes 1 arg
        expect(() => c.variants('v', {'v1': (x) {}}), throwsArgumentError);
      });

      test(
        'Benchmark constructor throws when batchSize passed without setup',
        () {
          expect(
            () => Benchmark('invalid', () {}, batchSize: BatchSize.smallInput),
            throwsArgumentError,
          );
        },
      );
    });

    group('Formatters and utilities', () {
      test('Benchmark.formatDuration formats all scales correctly', () {
        expect(Benchmark.formatDuration(0.5), contains('ps'));
        expect(Benchmark.formatDuration(500.0), contains('ns'));
        expect(Benchmark.formatDuration(50000.0), contains('μs'));
        expect(Benchmark.formatDuration(5000000.0), contains('ms'));
        expect(Benchmark.formatDuration(5000000000.0), contains('s'));
      });

      test('Benchmark.bold wraps in ANSI bold escape codes', () {
        expect(Benchmark.bold('test'), equals('\x1B[1mtest\x1B[22m'));
      });

      test('throughput rate formatting in benchmark run', () async {
        final c = Criterion(
          config: const CriterionConfig(
            generateHtmlReport: false,
            exportJson: false,
            useKbssd: false,
          ),
        );
        final prints = <String>[];
        c.bench(
          'bytes bench',
          () {},
          throughput: Throughput.bytes(500),
          samples: 5,
          warmupDuration: Duration.zero,
        );
        final results = await runZoned(
          () => c.run(),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => prints.add(line),
          ),
        );
        expect(results, hasLength(1));
        expect(results.first.throughput, isNotNull);
        expect(prints.any((l) => l.contains('throughput:')), isTrue);
        expect(prints.any((l) => l.contains('/s')), isTrue);
      });
    });
  });
}
