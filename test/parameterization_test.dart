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
  });
}
