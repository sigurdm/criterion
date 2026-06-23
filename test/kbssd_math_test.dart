import r"dart:math" as math;
import 'package:criterion/src/kbssd_math.dart';
import 'package:test/test.dart';

void main() {
  group('KBSSD Math', () {
    group('calculateMAD', () {
      test('simple odd length', () {
        final data = [1.0, 2.0, 3.0, 4.0, 5.0];
        final median = 3.0;
        // Deviations: 2, 1, 0, 1, 2
        // Sorted: 0, 1, 1, 2, 2
        // Median deviation: 1
        expect(calculateMAD(data, median), closeTo(1.0, 0.0001));
      });

      test('simple even length', () {
        final data = [1.0, 2.0, 3.0, 4.0];
        final median = 2.5;
        // Deviations: 1.5, 0.5, 0.5, 1.5
        // Sorted: 0.5, 0.5, 1.5, 1.5
        // Median deviation: (0.5 + 1.5) / 2 = 1.0
        expect(calculateMAD(data, median), closeTo(1.0, 0.0001));
      });

      test('empty data throws', () {
        expect(() => calculateMAD([], 0.0), throwsArgumentError);
      });
    });

    group('trimWindow', () {
      test('simple trim', () {
        final window = [
          10.0,
          1.0,
          5.0,
          3.0,
          2.0,
          4.0,
          6.0,
          7.0,
          8.0,
          9.0,
        ]; // 10 elements
        // Sorted: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
        // trim 10% -> k = round(10 * 0.1) = 1
        // Expected: 2, 3, 4, 5, 6, 7, 8, 9
        expect(
          trimWindow(window, 0.10),
          equals([2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]),
        );
      });

      test('trim rounds', () {
        final window = [1.0, 2.0, 3.0, 4.0, 5.0]; // 5 elements
        // trim 10% -> k = round(5 * 0.1) = round(0.5) = 1
        // Expected: 2, 3, 4
        expect(trimWindow(window, 0.10), equals([2.0, 3.0, 4.0]));

        // trim 4% -> k = round(5 * 0.04) = round(0.2) = 0
        // Expected: 1, 2, 3, 4, 5
        expect(trimWindow(window, 0.04), equals([1.0, 2.0, 3.0, 4.0, 5.0]));
      });

      test('empty window', () {
        expect(trimWindow([], 0.10), equals([]));
      });

      test('invalid trim percentage throws', () {
        expect(() => trimWindow([1.0], -0.1), throwsArgumentError);
        expect(() => trimWindow([1.0], 0.5), throwsArgumentError);
      });

      test('trimming too much returns empty', () {
        // window 2 elements, trim 40% -> k = round(2 * 0.4) = 1.
        // k * 2 = 2 >= 2 -> empty
        expect(trimWindow([1.0, 2.0], 0.40), equals([]));
      });
    });

    group('populationStandardDeviation', () {
      test('simple values', () {
        final values = [1.0, 2.0, 3.0, 4.0];
        // Mean = 2.5
        // Variance = (1.5^2 + 0.5^2 + 0.5^2 + 1.5^2) / 4 = (2.25 + 0.25 + 0.25 + 2.25) / 4 = 5 / 4 = 1.25
        // StdDev = sqrt(1.25) = 1.1180339887
        expect(
          populationStandardDeviation(values),
          closeTo(math.sqrt(1.25), 0.0001),
        );
      });

      test('empty values throws', () {
        expect(() => populationStandardDeviation([]), throwsArgumentError);
      });
    });

    group('standardErrorOfTheMean', () {
      test('simple values', () {
        final values = [1.0, 2.0, 3.0, 4.0];
        // StdDev = sqrt(1.25)
        // N = 4
        // SEM = sqrt(1.25) / sqrt(4) = sqrt(1.25) / 2 = 0.5590169944
        expect(
          standardErrorOfTheMean(values),
          closeTo(math.sqrt(1.25) / 2.0, 0.0001),
        );
      });

      test('empty values throws', () {
        expect(() => standardErrorOfTheMean([]), throwsArgumentError);
      });
    });

    group('calculateMMD', () {
      test('identical distributions', () {
        final X = [1.0, 2.0, 3.0];
        final Y = [1.0, 2.0, 3.0];
        expect(calculateMMD(X, Y, 1.0), closeTo(0.0, 0.0001));
      });

      test('different distributions', () {
        final X = [1.0, 2.0, 3.0];
        final Y = [10.0, 11.0, 12.0];
        // Expected MMD ~ 1.125 (calculated in thought)
        // Let's verify with actual implementation
        final sigma = 1.0;
        double kernel(double x, double y) =>
            math.exp(-(x - y) * (x - y) / (2.0 * sigma * sigma));

        double sumXX = 0.0;
        for (var x1 in X) {
          for (var x2 in X) {
            sumXX += kernel(x1, x2);
          }
        }
        double sumYY = 0.0;
        for (var y1 in Y) {
          for (var y2 in Y) {
            sumYY += kernel(y1, y2);
          }
        }
        double sumXY = 0.0;
        for (var x in X) {
          for (var y in Y) {
            sumXY += kernel(x, y);
          }
        }
        final m = X.length;
        final n = Y.length;
        final expectedMmdSquared =
            sumXX / (m * m) - 2.0 * sumXY / (m * n) + sumYY / (n * n);
        final expectedMmd = math.sqrt(math.max(0.0, expectedMmdSquared));

        expect(calculateMMD(X, Y, sigma), closeTo(expectedMmd, 0.0001));
      });

      test('empty X throws', () {
        expect(() => calculateMMD([], [1.0], 1.0), throwsArgumentError);
      });

      test('empty Y throws', () {
        expect(() => calculateMMD([1.0], [], 1.0), throwsArgumentError);
      });

      test('invalid sigma throws', () {
        expect(() => calculateMMD([1.0], [1.0], 0.0), throwsArgumentError);
        expect(() => calculateMMD([1.0], [1.0], -1.0), throwsArgumentError);
      });
    });

    group('checkSEM', () {
      test('low variance passes', () {
        final window = [1.0, 1.01, 0.99, 1.0];
        // Mean = 1.0
        // Variance: (0 + 0.0001 + 0.0001 + 0) / 4 = 0.00005
        // StdDev = sqrt(0.00005) = 0.007071
        // SEM = 0.007071 / 2 = 0.003535
        // SEM / Mean = 0.003535 / 1.0 = 0.003535
        // 0.003535 <= 0.03 (tolerance) -> true
        expect(checkSEM(window, tolerance: 0.03), isTrue);
      });

      test('high variance fails', () {
        final window = [1.0, 2.0, 3.0, 4.0];
        // SEM / Mean = 0.2236 (calculated in thought)
        // 0.2236 > 0.03 (tolerance) -> false
        expect(checkSEM(window, tolerance: 0.03), isFalse);
        // 0.2236 <= 0.30 (tolerance) -> true
        expect(checkSEM(window, tolerance: 0.30), isTrue);
      });

      test('empty window throws', () {
        expect(() => checkSEM([]), throwsArgumentError);
      });

      test('mean zero window', () {
        expect(checkSEM([0.0, 0.0, 0.0], tolerance: 0.03), isTrue);
        expect(checkSEM([-1.0, 1.0], tolerance: 0.03), isFalse);
      });
    });
  });
}
