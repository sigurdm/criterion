import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('KBSSD Integration', () {
    test('converges quickly for stable benchmark', () async {
      // We want the transition to happen after cold buffer (10 samples * ~10ms
      // = 100ms) plus some adaptive samples. Calibration takes ~20ms, so 200ms
      // should land during the detection loop.
      final stateful = StatefulTimeBenchmark(
        changeTimeMs: 200,
        slowMs: 2,
        fastMs: 1,
      );

      final prints = <String>[];
      final config = CriterionConfig(
        useKbssd: true,
        kbssdWindowSize: 5,
        kbssdStabilityRequired: 3,
        kbssdMaxSamples: 100,
      );

      List<BenchmarkResult>? results;
      await runZoned(
        () async {
          results = await criterion('test_suite', (c) {
            c.bench('stable_bench', stateful.run, samples: 6);
          }, config: config);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            prints.add(line);
          },
        ),
      );

      expect(results, isNotNull);
      expect(results!.length, equals(1));
      final result = results!.first;
      expect(result.primary.sampleTimes.length, equals(6));

      // It should have converged, so no steady-state warning.
      final hasWarning = prints.any(
        (p) => p.contains('did not reach a steady state'),
      );
      expect(hasWarning, isFalse, reason: 'Should not have warning: $prints');
    });

    test('warns and still samples if steady state is never reached', () async {
      final random = math.Random(42);
      void noisy() {
        final stack = StackTrace.current.toString();
        if (stack.contains('MemoryMeasurer') ||
            stack.contains('InstructionMeasurer')) {
          return;
        }
        // High variance
        final ms = random.nextInt(10) + 1; // 1 to 10 ms
        sleep(Duration(milliseconds: ms));
      }

      final prints = <String>[];
      final config = CriterionConfig(
        useKbssd: true,
        kbssdWindowSize: 5,
        kbssdStabilityRequired: 5,
        kbssdMaxSamples: 15,
        kbssdScaleFactor: 0.1,
      );

      List<BenchmarkResult>? results;
      await runZoned(
        () async {
          results = await criterion('test_suite', (c) {
            c.bench('noisy_bench', noisy, samples: 4);
          }, config: config);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            prints.add(line);
          },
        ),
      );

      expect(results, isNotNull);
      expect(results!.length, equals(1));
      final result = results!.first;
      // Even without convergence, the requested samples are still collected.
      expect(result.primary.sampleTimes.length, equals(4));

      final hasWarning = prints.any(
        (p) => p.contains('did not reach a steady state'),
      );
      expect(hasWarning, isTrue, reason: 'Should have warning: $prints');
    });

    test('samples is honoured whether or not KBSSD is enabled', () async {
      // Regression test: KBSSD used to ignore `samples` entirely and always
      // report exactly `kbssdWindowSize` values, so every statistic was
      // computed on 15 points regardless of what the caller asked for.
      Future<int> sampleCountWith({required bool useKbssd}) async {
        final results = await criterion(
          'sample_count',
          (c) {
            c.bench(
              'trivial',
              () => blackhole(1 + 1),
              samples: 9,
              warmupDuration: const Duration(milliseconds: 5),
            );
          },
          config: CriterionConfig(
            useKbssd: useKbssd,
            kbssdWindowSize: 3,
            kbssdStabilityRequired: 2,
            kbssdMaxSamples: 30,
            generateHtmlReport: false,
            exportJson: false,
            exportHistory: false,
            measureMemory: false,
            measureInstructions: false,
            measureCycles: false,
          ),
        );
        return results.single.primary.sampleTimes.length;
      }

      expect(await sampleCountWith(useKbssd: true), equals(9));
      expect(await sampleCountWith(useKbssd: false), equals(9));
    });
  });
}

class StatefulTimeBenchmark {
  final Stopwatch _stopwatch = Stopwatch()..start();
  final int changeTimeMs;
  final int slowMs;
  final int fastMs;

  StatefulTimeBenchmark({
    required this.changeTimeMs,
    required this.slowMs,
    required this.fastMs,
  });

  void run() {
    final stack = StackTrace.current.toString();
    if (stack.contains('MemoryMeasurer') ||
        stack.contains('InstructionMeasurer')) {
      return;
    }
    if (_stopwatch.elapsedMilliseconds < changeTimeMs) {
      sleep(Duration(milliseconds: slowMs));
    } else {
      sleep(Duration(milliseconds: fastMs));
    }
  }
}
