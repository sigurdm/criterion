import 'dart:async';
import 'dart:io';
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

    test(
      'Console report formats low-rate throughput (B/s, KB/s, MB/s, small count)',
      () async {
        final printLines = <String>[];
        await runZonedGuarded(
          () async {
            final c = Criterion(
              config: const CriterionConfig(
                generateHtmlReport: false,
                exportJson: false,
                useKbssd: false,
              ),
            );
            // 1 byte per iteration with 2ms sleep ~ 500 B/s (< 1024 B/s)
            c.bench(
              'low_bytes_bench',
              () {
                sleep(const Duration(milliseconds: 2));
              },
              throughput: const Throughput.bytes(1),
              samples: 2,
              warmupDuration: Duration.zero,
            );
            // 1 element per iteration with 2ms sleep ~ 500 elements/s (< 1000 elements/s)
            c.bench(
              'low_elements_bench',
              () {
                sleep(const Duration(milliseconds: 2));
              },
              throughput: const Throughput.elements(1),
              samples: 2,
              warmupDuration: Duration.zero,
            );
            // 100 bytes with 1ms sleep ~ 100 KB/s (< 1024 KB/s)
            c.bench(
              'kb_bytes_bench',
              () {
                sleep(const Duration(milliseconds: 1));
              },
              throughput: const Throughput.bytes(100),
              samples: 2,
              warmupDuration: Duration.zero,
            );
            // 100000 bytes with 1ms sleep ~ 100 MB/s (< 1024 MB/s)
            c.bench(
              'mb_bytes_bench',
              () {
                sleep(const Duration(milliseconds: 1));
              },
              throughput: const Throughput.bytes(100000),
              samples: 2,
              warmupDuration: Duration.zero,
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

        expect(printLines.any((l) => l.contains(' B/s')), isTrue);
        expect(printLines.any((l) => l.contains(' KB/s')), isTrue);
        expect(printLines.any((l) => l.contains(' MB/s')), isTrue);
        expect(printLines.any((l) => l.contains(' elements/s')), isTrue);
      },
    );
  });
}
