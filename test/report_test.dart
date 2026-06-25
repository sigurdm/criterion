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

import 'dart:convert';
import 'dart:io';
import 'package:criterion/criterion.dart';
import 'package:criterion/src/cycle_counter.dart';
import 'package:test/test.dart';

void main() {
  group('Criterion Reporting', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('criterion_report_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('generates JSON and HTML reports', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: true,
        exportJson: true,
        useKbssd: false,
      );

      final results = await criterion('Test Suite', (c) {
        c.bench(
          'bench1',
          () {
            var sum = 0;
            for (var i = 0; i < 100; i++) {
              sum += i;
            }
            if (sum == 0) throw StateError('invalid sum');
          },
          noOp: () {
            // no-op
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
        c.bench(
          'bench2',
          () {
            var sum = 0;
            for (var i = 0; i < 200; i++) {
              sum += i;
            }
            if (sum == 0) throw StateError('invalid sum');
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      expect(results.length, equals(2));

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isTrue);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isTrue);

      // Verify JSON content
      final jsonContent = jsonFile.readAsStringSync();
      final decoded = jsonDecode(jsonContent) as List;
      expect(decoded.length, equals(2));

      final firstResult = decoded[0] as Map<String, dynamic>;
      expect(firstResult['name'], equals('bench1'));
      expect(firstResult['iterations'], isNotNull);
      expect(firstResult['primary'], isNotNull);

      final primary = firstResult['primary'] as Map<String, dynamic>;
      expect(primary['sampleTimes'], isList);
      expect((primary['sampleTimes'] as List).length, equals(5));
      expect(primary['mean'], isNotNull);
      expect(primary['median'], isNotNull);
      expect(primary['stdDev'], isNotNull);
      expect(primary['meanCI'], isNotNull);
      expect(primary['medianCI'], isNotNull);
      expect(primary['outliers'], isNotNull);
      if (CycleCounter.isSupported) {
        expect(primary['cyclesPerIteration'], isNotNull);
      }

      final net = firstResult['net'] as Map<String, dynamic>?;
      expect(net, isNotNull);
      expect(net!['timeNs'], isNotNull);
      if (CycleCounter.isSupported) {
        expect(net['cycles'], isNotNull);
      }

      // Verify HTML content contains the data
      final htmlContent = htmlFile.readAsStringSync();
      expect(htmlContent, contains('const data = ['));
      expect(htmlContent, contains('"name":"bench1"'));
      expect(htmlContent, contains('"name":"bench2"'));
      expect(htmlContent, contains('https://cdn.jsdelivr.net/npm/chart.js'));
      expect(htmlContent, contains('classAllocations'));
      expect(htmlContent, contains('memory-allocations-table'));
      expect(htmlContent, contains('cpuProfile'));
      expect(htmlContent, contains('cpu-profile-table'));
    });

    test('respects config to disable reports', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: false,
      );

      await criterion('Test Suite Disabled', (c) {
        c.bench(
          'bench1',
          () {},
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isFalse);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isFalse);
    });

    test('JSON roundtrip deserialization', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: true,
      );

      final originalResults = await criterion('Test Suite', (c) {
        c.bench(
          'bench1',
          () {},
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      expect(originalResults.length, equals(1));
      final original = originalResults.first;

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isTrue);

      final jsonContent = jsonFile.readAsStringSync();
      final decodedList = jsonDecode(jsonContent) as List;
      expect(decodedList.length, equals(1));

      final deserialized = BenchmarkResult.fromJson(
        decodedList.first as Map<String, dynamic>,
      );

      expect(deserialized.name, equals(original.name));
      expect(deserialized.iterations, equals(original.iterations));
      _compareMeasurementResults(deserialized.primary, original.primary);
      expect(deserialized.noOp, isNull);
      expect(deserialized.net, isNull);
    });

    test('JSON roundtrip deserialization with noOp calibration', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: false,
        exportJson: true,
      );

      final originalResults = await criterion('Test Suite FFI', (c) {
        c.bench(
          'ffi-mock',
          () {
            var sum = 0;
            for (var i = 0; i < 1000; i++) {
              sum += i;
            }
            if (sum == 0) throw StateError('invalid sum');
          },
          noOp: () {
            // Simulate no-op
          },
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      expect(originalResults.length, equals(1));
      final original = originalResults.first;

      final jsonFile = File('${tempDir.path}/results.json');
      expect(jsonFile.existsSync(), isTrue);

      final jsonContent = jsonFile.readAsStringSync();
      final decodedList = jsonDecode(jsonContent) as List;
      expect(decodedList.length, equals(1));

      final deserialized = BenchmarkResult.fromJson(
        decodedList.first as Map<String, dynamic>,
      );

      expect(deserialized.name, equals(original.name));
      expect(deserialized.iterations, equals(original.iterations));
      _compareMeasurementResults(deserialized.primary, original.primary);

      expect(original.noOp, isNotNull);
      expect(deserialized.noOp, isNotNull);
      _compareMeasurementResults(deserialized.noOp!, original.noOp!);

      expect(original.net, isNotNull);
      expect(deserialized.net, isNotNull);
      _compareNetResults(deserialized.net, original.net);
    });

    test('generates HTML report with parameterized benchmarks', () async {
      final config = CriterionConfig(
        reportDir: tempDir.path,
        generateHtmlReport: true,
        exportJson: false,
        useKbssd: false,
      );

      await criterion('Param Test Suite', (c) {
        c.benchWith<void, int>(
          'fib',
          [10, 20],
          (n) {},
          samples: 5,
          warmupDuration: const Duration(milliseconds: 5),
        );
      }, config: config);

      final htmlFile = File('${tempDir.path}/index.html');
      expect(htmlFile.existsSync(), isTrue);

      final htmlContent = htmlFile.readAsStringSync();
      expect(htmlContent, contains('"parameterGroup":"fib"'));
      expect(htmlContent, contains('"parameterValue":10'));
      expect(htmlContent, contains('"parameterValue":20'));
      expect(htmlContent, contains('parameterGroups'));
      expect(htmlContent, contains('generateParameterCharts'));
    });
  });
}

void _compareMeasurementResults(
  MeasurementResult actual,
  MeasurementResult expected,
) {
  expect(actual.sampleTimes, equals(expected.sampleTimes));
  expect(actual.mean, closeTo(expected.mean, 1e-9));
  expect(actual.median, closeTo(expected.median, 1e-9));
  expect(actual.stdDev, closeTo(expected.stdDev, 1e-9));

  expect(actual.meanCI.lowerBound, closeTo(expected.meanCI.lowerBound, 1e-9));
  expect(actual.meanCI.upperBound, closeTo(expected.meanCI.upperBound, 1e-9));
  expect(
    actual.medianCI.lowerBound,
    closeTo(expected.medianCI.lowerBound, 1e-9),
  );
  expect(
    actual.medianCI.upperBound,
    closeTo(expected.medianCI.upperBound, 1e-9),
  );

  expect(actual.outliers.lowSevere, equals(expected.outliers.lowSevere));
  expect(actual.outliers.lowMild, equals(expected.outliers.lowMild));
  expect(actual.outliers.highMild, equals(expected.outliers.highMild));
  expect(actual.outliers.highSevere, equals(expected.outliers.highSevere));
  expect(
    actual.outliers.outlierVariancePercentage,
    closeTo(expected.outliers.outlierVariancePercentage, 1e-9),
  );

  if (expected.memory != null) {
    expect(actual.memory, isNotNull);
    if (expected.memory!.allocatedBytesPerIteration == null) {
      expect(actual.memory!.allocatedBytesPerIteration, isNull);
    } else {
      expect(
        actual.memory!.allocatedBytesPerIteration,
        closeTo(expected.memory!.allocatedBytesPerIteration!, 1e-9),
      );
    }
    if (expected.memory!.allocatedObjectsPerIteration == null) {
      expect(actual.memory!.allocatedObjectsPerIteration, isNull);
    } else {
      expect(
        actual.memory!.allocatedObjectsPerIteration,
        closeTo(expected.memory!.allocatedObjectsPerIteration!, 1e-9),
      );
    }
    expect(
      actual.memory!.rssDeltaBytes,
      equals(expected.memory!.rssDeltaBytes),
    );
  } else {
    expect(actual.memory, isNull);
  }

  if (expected.instructions != null) {
    expect(actual.instructions, isNotNull);
    expect(
      actual.instructions!.instructionsPerIteration,
      closeTo(expected.instructions!.instructionsPerIteration, 1e-9),
    );
  } else {
    expect(actual.instructions, isNull);
  }
}

void _compareNetResults(NetResult? actual, NetResult? expected) {
  if (expected == null) {
    expect(actual, isNull);
    return;
  }
  expect(actual, isNotNull);
  expect(actual!.timeNs, closeTo(expected.timeNs, 1e-9));
  if (expected.allocatedBytes == null) {
    expect(actual.allocatedBytes, isNull);
  } else {
    expect(actual.allocatedBytes, closeTo(expected.allocatedBytes!, 1e-9));
  }
  if (expected.allocatedObjects == null) {
    expect(actual.allocatedObjects, isNull);
  } else {
    expect(actual.allocatedObjects, closeTo(expected.allocatedObjects!, 1e-9));
  }
  if (expected.instructions == null) {
    expect(actual.instructions, isNull);
  } else {
    expect(actual.instructions, closeTo(expected.instructions!, 1e-9));
  }
}
