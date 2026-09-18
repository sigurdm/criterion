import 'dart:async';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Setup/Teardown', () {
    test('State isolation and passing', () async {
      final statesCreated = <int>[];
      final statesReceived = <int>[];
      var counter = 0;

      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );
      c.bench<int>(
        'setup_bench',
        (int state) {
          statesReceived.add(state);
        },
        setup: () {
          counter++;
          statesCreated.add(counter);
          return counter;
        },
        samples: 5,
        warmupDuration: const Duration(milliseconds: 10),
      );

      await c.run();

      // Ensure setup was called and states were passed
      expect(statesCreated, isNotEmpty);
      expect(statesReceived, isNotEmpty);
      expect(statesReceived.length, statesCreated.length);

      // Check that each iteration got a unique state in increasing order
      for (var i = 0; i < statesReceived.length; i++) {
        expect(statesReceived[i], statesCreated[i]);
      }

      // Check that states are unique (isolation)
      expect(statesReceived.toSet().length, statesReceived.length);
    });

    test('Async setup and async fn', () async {
      final statesCreated = <int>[];
      final statesReceived = <int>[];
      var counter = 0;

      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );
      c.bench<int>(
        'async_setup_bench',
        (int state) async {
          await Future.delayed(const Duration(milliseconds: 1));
          statesReceived.add(state);
        },
        setup: () async {
          await Future.delayed(const Duration(milliseconds: 1));
          counter++;
          statesCreated.add(counter);
          return counter;
        },
        samples: 5,
        warmupDuration: const Duration(milliseconds: 10),
      );

      await c.run();

      expect(statesCreated, isNotEmpty);
      expect(statesReceived, isNotEmpty);
      expect(statesReceived.length, statesCreated.length);
      for (var i = 0; i < statesReceived.length; i++) {
        expect(statesReceived[i], statesCreated[i]);
      }
    });

    test('teardown without setup throws ArgumentError', () {
      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );

      expect(
        () => c.bench('bad_bench', () {}, teardown: (_) {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('teardown can only be provided when setup is provided'),
          ),
        ),
      );

      expect(
        () => c.variants('bad_variants', {'v1': () {}}, teardown: (_) {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('teardown can only be provided when setup is provided'),
          ),
        ),
      );

      expect(
        () => c.benchWith<dynamic, int>(
          'bad_benchWith',
          [1, 2],
          (p) {},
          teardown: (_) {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('teardown can only be provided when setup is provided'),
          ),
        ),
      );

      expect(
        () => Benchmark('bad_benchmark_ctor', () {}, teardown: (_) {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('teardown can only be provided when setup is provided'),
          ),
        ),
      );
    });

    test(
      'teardown is called once for every setup call in BatchSize.perIteration and BatchSize.smallInput',
      () async {
        for (final mode in [BatchSize.perIteration, BatchSize.smallInput]) {
          final setups = <int>[];
          final teardowns = <int>[];
          var counter = 0;

          final c = Criterion(
            config: const CriterionConfig(
              generateHtmlReport: false,
              exportJson: false,
            ),
          );
          c.bench<int>(
            'teardown_counter_$mode',
            (state) {
              // Small busy delay so calibrate targets a small iteration count (e.g. 10-50 iterations)
              final sw = Stopwatch()..start();
              while (sw.elapsedMicroseconds < 200) {}
              blackhole(state);
            },
            setup: () {
              counter++;
              setups.add(counter);
              return counter;
            },
            teardown: (state) {
              teardowns.add(state);
            },
            batchSize: mode,
            samples: 3,
            warmupDuration: const Duration(milliseconds: 5),
          );

          await c.run();

          expect(setups, isNotEmpty);
          expect(teardowns, isNotEmpty);
          expect(teardowns.length, equals(setups.length));
          expect(teardowns, equals(setups));
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('teardown works with bench, variants, and benchWith', () async {
      // bench
      final benchTeardowns = <String>[];
      // variants
      final variantTeardowns = <String>[];
      // benchWith
      final paramTeardowns = <String>[];

      final c = Criterion(
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );

      c.bench<String>(
        'bench_single',
        (state) {},
        setup: () => 'bench_state',
        teardown: (state) => benchTeardowns.add(state),
        samples: 5,
        warmupDuration: const Duration(milliseconds: 5),
      );

      c.variants<String>(
        'variant_group',
        {'v1': (state) {}, 'v2': (state) {}},
        setup: () => 'variant_state',
        teardown: (state) => variantTeardowns.add(state),
        samples: 5,
        warmupDuration: const Duration(milliseconds: 5),
      );

      c.benchWith<String, int>(
        'param_group',
        [10, 20],
        (String state, int param) {},
        setup: (param) => 'param_$param',
        teardown: (state) => paramTeardowns.add(state),
        samples: 5,
        warmupDuration: const Duration(milliseconds: 5),
      );

      await c.run();

      expect(benchTeardowns, isNotEmpty);
      expect(benchTeardowns.every((s) => s == 'bench_state'), isTrue);

      expect(variantTeardowns, isNotEmpty);
      expect(variantTeardowns.every((s) => s == 'variant_state'), isTrue);

      expect(paramTeardowns, isNotEmpty);
      expect(paramTeardowns.any((s) => s == 'param_10'), isTrue);
      expect(paramTeardowns.any((s) => s == 'param_20'), isTrue);
    });

    test(
      'async teardown is properly awaited and excluded from measured duration',
      () async {
        var teardownCount = 0;
        final c = Criterion(
          config: const CriterionConfig(
            generateHtmlReport: false,
            exportJson: false,
          ),
        );

        c.bench<int>(
          'async_teardown_time_exclusion',
          (state) {
            // Fast operation (nanoseconds)
            blackhole(state * 2);
          },
          setup: () => 42,
          teardown: (state) async {
            // 20ms simulated async cleanup
            await Future.delayed(const Duration(milliseconds: 20));
            teardownCount++;
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 10),
        );

        final results = await c.run();
        expect(teardownCount, greaterThan(0));
        expect(results.length, equals(1));

        // The measured primary mean time per iteration must NOT include the 20ms teardown time!
        // 20ms = 20,000,000 ns. The fast multiplication loop should measure well under 100,000 ns.
        final meanNs = results.first.primary.mean;
        expect(
          meanNs,
          lessThan(100000),
          reason:
              'Teardown time must be excluded from measured duration (was ${meanNs}ns)',
        );
      },
    );
  });
}
