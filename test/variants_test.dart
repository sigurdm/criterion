import 'dart:async';
import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Benchmark Variants', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('criterion_variants_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('variants API registers benchmarks with metadata', () {
      final c = Criterion();
      c.variants('fib', {'recursive': () {}, 'iterative': () {}});

      expect(c.benchmarks.length, equals(2));
      expect(c.benchmarks[0].name, equals('fib / recursive'));
      expect(c.benchmarks[0].variantGroup, equals('fib'));
      expect(c.benchmarks[0].variantName, equals('recursive'));

      expect(c.benchmarks[1].name, equals('fib / iterative'));
      expect(c.benchmarks[1].variantGroup, equals('fib'));
      expect(c.benchmarks[1].variantName, equals('iterative'));
    });

    test('variants API works within groups', () {
      final c = Criterion();
      c.group('Math', () {
        c.variants('Fibonacci', {'recursive': () {}, 'iterative': () {}});
      });

      expect(c.benchmarks.length, equals(2));

      final b1 = c.benchmarks[0];
      expect(b1.name, equals('Math / Fibonacci / recursive'));
      expect(
        b1.variantGroup,
        equals('Fibonacci'),
      ); // variantGroup should not include group path
      expect(b1.variantName, equals('recursive'));

      final b2 = c.benchmarks[1];
      expect(b2.name, equals('Math / Fibonacci / iterative'));
      expect(
        b2.variantGroup,
        equals('Fibonacci'),
      ); // variantGroup should not include group path
      expect(b2.variantName, equals('iterative'));
    });

    test('BenchmarkResult serializes/deserializes variant metadata', () {
      final primary = MeasurementResult(
        sampleTimes: [1.0, 2.0],
        mean: 1.5,
        median: 1.5,
        stdDev: 0.5,
        meanCI: ConfidenceInterval(lowerBound: 1.0, upperBound: 2.0),
        medianCI: ConfidenceInterval(lowerBound: 1.0, upperBound: 2.0),
        outliers: OutlierAnalysis(
          lowSevere: 0,
          lowMild: 0,
          highMild: 0,
          highSevere: 0,
          outlierVariancePercentage: 0.0,
        ),
      );
      final result = BenchmarkResult(
        name: 'fib / recursive',
        iterations: 1,
        primary: primary,
        variantGroup: 'fib',
        variantName: 'recursive',
      );

      final json = result.toJson();
      expect(json['variantGroup'], equals('fib'));
      expect(json['variantName'], equals('recursive'));

      final deserialized = BenchmarkResult.fromJson(json);
      expect(deserialized.variantGroup, equals('fib'));
      expect(deserialized.variantName, equals('recursive'));
    });

    test(
      'fromJson handles missing variant metadata (backward compatibility)',
      () {
        final primary = MeasurementResult(
          sampleTimes: [1.0, 2.0],
          mean: 1.5,
          median: 1.5,
          stdDev: 0.5,
          meanCI: ConfidenceInterval(lowerBound: 1.0, upperBound: 2.0),
          medianCI: ConfidenceInterval(lowerBound: 1.0, upperBound: 2.0),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        );
        final result = BenchmarkResult(
          name: 'fib / recursive',
          iterations: 1,
          primary: primary,
        );

        final json = result.toJson();
        expect(json.containsKey('variantGroup'), isFalse);
        expect(json.containsKey('variantName'), isFalse);

        final deserialized = BenchmarkResult.fromJson(json);
        expect(deserialized.variantGroup, isNull);
        expect(deserialized.variantName, isNull);
      },
    );

    test('prints comparison table to stdout', () async {
      final printLines = <String>[];
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: false,
      );

      await runZonedGuarded(
        () async {
          await criterion('Variants Test', (c) {
            c.variants(
              'Fibonacci',
              {
                'recursive': () {
                  // simulate some work
                  var a = 0;
                  for (var i = 0; i < 1000; i++) {
                    a += i;
                  }
                  if (a == -1) print(a);
                },
                'iterative': () {
                  // simulate faster work
                  var a = 0;
                  for (var i = 0; i < 100; i++) {
                    a += i;
                  }
                  if (a == -1) print(a);
                },
              },
              samples: 5,
              warmupDuration: const Duration(milliseconds: 5),
            );
          }, config: config);
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

      // Verify comparison table in stdout
      expect(
        printLines,
        anyElement(contains('=== Variant Comparison: Fibonacci ===')),
      );
      expect(
        printLines,
        anyElement(
          contains('| Variant | Time | Relative Speed | Significant? |'),
        ),
      );
      expect(printLines, anyElement(contains('recursive (baseline)')));
      expect(printLines, anyElement(contains('iterative')));
    });

    test('HTML report contains variant data', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: true,
        exportJson: false,
      );

      await criterion('Variants HTML Test', (c) {
        c.variants(
          'Fibonacci',
          {'recursive': () {}, 'iterative': () {}},
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isTrue);

      final htmlContent = htmlFile.readAsStringSync();
      expect(htmlContent, contains('"variantGroup":"Fibonacci"'));
      expect(htmlContent, contains('"variantName":"recursive"'));
      expect(htmlContent, contains('"variantName":"iterative"'));
      expect(htmlContent, contains('variants-mode-container'));
      expect(htmlContent, contains('variants-view'));
    });
  });
}
