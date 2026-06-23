import 'dart:async';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('Throughput', () {
    test('JSON serialization roundtrip', () {
      final result = BenchmarkResult(
        name: 'test_bench',
        iterations: 1,
        primary: MeasurementResult(
          sampleTimes: [10.0],
          mean: 10.0,
          median: 10.0,
          stdDev: 0.0,
          meanCI: ConfidenceInterval(lowerBound: 10.0, upperBound: 10.0),
          medianCI: ConfidenceInterval(lowerBound: 10.0, upperBound: 10.0),
          outliers: OutlierAnalysis(
            lowSevere: 0,
            lowMild: 0,
            highMild: 0,
            highSevere: 0,
            outlierVariancePercentage: 0.0,
          ),
        ),
        throughput: const Throughput.bytes(1024),
      );

      final json = result.toJson();
      expect(json['throughput'], isNotNull);
      expect(json['throughput']['count'], 1024);
      expect(json['throughput']['unit'], 'bytes');

      final deserialized = BenchmarkResult.fromJson(json);
      expect(deserialized.throughput, isNotNull);
      expect(deserialized.throughput!.count, 1024);
      expect(deserialized.throughput!.unit, ThroughputUnit.bytes);
    });

    test('Console report formats bytes throughput', () async {
      final printLines = <String>[];
      await runZonedGuarded(
        () async {
          final c = Criterion(
            config: const CriterionConfig(
              generateHtmlReport: false,
              exportJson: false,
            ),
          );
          c.bench(
            'bytes_bench',
            () {},
            throughput: const Throughput.bytes(1024 * 1024),
            samples: 10,
            warmupDuration: const Duration(milliseconds: 10),
          );
          await c.run();
        },
        (e, s) => fail('Run failed: $e'),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printLines.add(line);
          },
        ),
      );

      final throughputLine = printLines.firstWhere(
        (line) => line.contains('throughput:'),
        orElse: () => '',
      );
      expect(throughputLine, isNotEmpty);
      expect(throughputLine, contains('/s'));
      print('Found throughput line: $throughputLine');
    });

    test('Console report formats elements throughput', () async {
      final printLines = <String>[];
      await runZonedGuarded(
        () async {
          final c = Criterion(
            config: const CriterionConfig(
              generateHtmlReport: false,
              exportJson: false,
            ),
          );
          c.bench(
            'elements_bench',
            () {},
            throughput: const Throughput.elements(1000),
            samples: 10,
            warmupDuration: const Duration(milliseconds: 10),
          );
          await c.run();
        },
        (e, s) => fail('Run failed: $e'),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printLines.add(line);
          },
        ),
      );

      final throughputLine = printLines.firstWhere(
        (line) => line.contains('throughput:'),
        orElse: () => '',
      );
      expect(throughputLine, isNotEmpty);
      expect(throughputLine, contains('elements/s'));
      print('Found throughput line: $throughputLine');
    });
  });
}
