import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('KBSSD Integration', () {
    test('converges quickly for stable benchmark', () async {
      // We want the transition to happen after cold buffer (10 samples * ~10ms = 100ms)
      // plus some adaptive samples.
      // Calibration takes ~20ms.
      // So 200ms should be during the adaptive loop.
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
            c.bench('stable_bench', stateful.run);
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
      expect(result.primary.sampleTimes.length, equals(5)); // kbssdWindowSize

      // It should have converged, so no warning about not converging
      final hasWarning = prints.any((p) => p.contains('did not converge'));
      expect(hasWarning, isFalse, reason: 'Should not have warning: $prints');
    });

    test('warns and falls back if not converged', () async {
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
            c.bench('noisy_bench', noisy);
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
      expect(result.primary.sampleTimes.length, equals(5)); // kbssdWindowSize

      // It should have warned
      final hasWarning = prints.any((p) => p.contains('did not converge'));
      expect(hasWarning, isTrue, reason: 'Should have warning: $prints');
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
