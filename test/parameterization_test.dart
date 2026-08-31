import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Parameterization (benchWith)', () {
    test('runs benchmarks with parameters and correct naming', () async {
      final results = await criterion(
        'Param Test',
        (c) {
          c.benchWith<void, int>(
            'fib',
            [10, 20],
            (n) {
              // Do some dummy work that depends on n
              var sum = 0;
              for (var i = 0; i < n; i++) {
                sum += i;
              }
              blackhole(sum);
            },
            samples: 5, // Small samples for fast test
          );
        },
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );

      expect(results.length, equals(2));

      final r1 = results[0];
      expect(r1.name, equals('fib / 10'));
      expect(r1.parameterGroup, equals('fib'));
      expect(r1.parameterValue, equals(10));

      final r2 = results[1];
      expect(r2.name, equals('fib / 20'));
      expect(r2.parameterGroup, equals('fib'));
      expect(r2.parameterValue, equals(20));
    });

    test('supports setup with parameter', () async {
      final results = await criterion(
        'Param Setup Test',
        (c) {
          c.benchWith<List<int>, int>(
            'sort',
            [5, 10],
            (list) {
              list.sort();
            },
            setup: (size) => List<int>.generate(size, (i) => size - i),
            samples: 5,
          );
        },
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );

      expect(results.length, equals(2));

      final r1 = results[0];
      expect(r1.name, equals('sort / 5'));
      expect(r1.parameterGroup, equals('sort'));
      expect(r1.parameterValue, equals(5));

      final r2 = results[1];
      expect(r2.name, equals('sort / 10'));
      expect(r2.parameterGroup, equals('sort'));
      expect(r2.parameterValue, equals(10));
    });

    test('JSON serialization roundtrip preserves parameter info', () async {
      final results = await criterion(
        'Param JSON Test',
        (c) {
          c.benchWith<void, String>('print', ['a', 'b'], (s) {
            // dummy
          }, samples: 5);
        },
        config: const CriterionConfig(
          generateHtmlReport: false,
          exportJson: false,
        ),
      );

      expect(results.length, equals(2));

      for (final r in results) {
        final json = r.toJson();
        final deserialized = BenchmarkResult.fromJson(json);
        expect(deserialized.parameterGroup, equals(r.parameterGroup));
        expect(deserialized.parameterValue, equals(r.parameterValue));
      }
    });

    test('serializes custom non-primitive parameter objects', () {
      final paramObj = _CustomParam('test');
      final r = BenchmarkResult(
        name: 'custom_bench',
        iterations: 100,
        platform: 'jit',
        timestamp: DateTime.now(),
        primary: MeasurementResult(
          sampleTimes: [10.0, 20.0],
          mean: 15.0,
          median: 15.0,
          stdDev: 5.0,
          meanCI: ConfidenceInterval(lowerBound: 10.0, upperBound: 20.0),
          medianCI: ConfidenceInterval(lowerBound: 10.0, upperBound: 20.0),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
        parameterGroup: 'custom',
        parameterValue: paramObj,
      );
      final json = r.toJson();
      expect(json['parameterValue'], equals('Custom(test)'));
    });

    test(
      'benchWith supports nested groups, (state, param) signature, noOp, and throughput',
      () async {
        final c = Criterion(
          config: const CriterionConfig(
            generateHtmlReport: false,
            exportJson: false,
          ),
        );

        c.group('math', () {
          c.benchWith<List<int>, int>(
            'add',
            [2],
            (list, p) {
              list.add(p);
            },
            setup: (p) => <int>[p],
            noOp: (list, p) {
              // noOp matching state and param
            },
            throughput: (p) => Throughput.elements(p),
            samples: 5,
            warmupDuration: Duration.zero,
          );
        });

        expect(c.benchmarks.length, equals(1));
        expect(c.benchmarks.first.name, equals('math / add / 2'));

        final results = await c.run();
        expect(results.length, equals(1));
        expect(results.first.parameterValue, equals(2));
        expect(results.first.throughput, isNotNull);
      },
    );

    test(
      'benchWith throws ArgumentError when parameterless fn provided without setup',
      () {
        final c = Criterion();
        expect(
          () => c.benchWith<void, int>(
            'invalid',
            [1, 2],
            () {}, // takes 0 arguments instead of 1
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

class _CustomParam {
  final String label;
  _CustomParam(this.label);
  @override
  String toString() => 'Custom($label)';
}
