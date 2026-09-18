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

import 'dart:io';

import 'package:criterion/criterion.dart';
import 'package:criterion/src/history.dart';
import 'package:criterion/src/history_trim.dart';
import 'package:test/test.dart';

BenchmarkResult _result(
  String name, {
  DateTime? timestamp,
  String? parameterValue,
  double mean = 1.0,
}) => BenchmarkResult(
  name: name,
  iterations: 1,
  timestamp: timestamp,
  parameterValue: parameterValue,
  primary: MeasurementResult(
    mean: mean,
    median: mean,
    stdDev: 0.0,
    meanCI: ConfidenceInterval(lowerBound: mean, upperBound: mean),
    medianCI: ConfidenceInterval(lowerBound: mean, upperBound: mean),
    outliers: OutlierAnalysis(
      lowSevere: 0,
      lowMild: 0,
      highMild: 0,
      highSevere: 0,
      outlierVariancePercentage: 0.0,
    ),
    sampleTimes: [mean],
  ),
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('criterion_durability_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('trimHistory', () {
    test('returns the list unchanged when nothing needs trimming', () {
      final history = [_result('a'), _result('b')];
      expect(trimHistory(history, maxEntriesPerBenchmark: 10), same(history));
    });

    test('keeps the most recent entries per benchmark', () {
      final base = DateTime.utc(2020);
      final history = [
        for (var i = 0; i < 5; i++)
          _result(
            'a',
            timestamp: base.add(Duration(days: i)),
            mean: i + 1,
          ),
      ];

      final trimmed = trimHistory(history, maxEntriesPerBenchmark: 2);

      expect(trimmed, hasLength(2));
      expect(
        trimmed.map((r) => r.primary.mean),
        orderedEquals([4.0, 5.0]),
        reason: 'the two newest should survive, in original order',
      );
    });

    test('caps each benchmark independently', () {
      final base = DateTime.utc(2020);
      final history = [
        for (var i = 0; i < 5; i++)
          _result('noisy', timestamp: base.add(Duration(days: i))),
        _result('quiet', timestamp: base),
      ];

      final trimmed = trimHistory(history, maxEntriesPerBenchmark: 2);

      expect(trimmed.where((r) => r.name == 'noisy'), hasLength(2));
      expect(
        trimmed.where((r) => r.name == 'quiet'),
        hasLength(1),
        reason: 'a rarely-run benchmark must not be evicted by a busy one',
      );
    });

    test('treats different parameter values as different benchmarks', () {
      final base = DateTime.utc(2020);
      final history = [
        for (var i = 0; i < 3; i++)
          _result(
            'p',
            timestamp: base.add(Duration(days: i)),
            parameterValue: '10',
          ),
        for (var i = 0; i < 3; i++)
          _result(
            'p',
            timestamp: base.add(Duration(days: i)),
            parameterValue: '20',
          ),
      ];

      final trimmed = trimHistory(history, maxEntriesPerBenchmark: 1);

      expect(trimmed, hasLength(2));
      expect(
        trimmed.map((r) => r.parameterValue).toSet(),
        unorderedEquals(<Object?>['10', '20']),
      );
    });

    test('rejects a cap below 1', () {
      expect(
        () => trimHistory([], maxEntriesPerBenchmark: 0),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'maxEntriesPerBenchmark',
          ),
        ),
      );
    });
  });

  group('HistoryManager durability', () {
    test('a corrupt history file is quarantined, not overwritten', () async {
      final path = '${tempDir.path}/history.json';
      File(path).writeAsStringSync('{ this is not valid json');

      final mgr = HistoryManager(path);
      expect(await mgr.load(), isEmpty);

      final quarantined = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'))
          .toList();
      expect(
        quarantined,
        hasLength(1),
        reason: 'the unparseable file must be preserved',
      );
      expect(quarantined.single.readAsStringSync(), '{ this is not valid json');
      expect(
        File(path).existsSync(),
        isFalse,
        reason: 'it was moved aside, not copied',
      );

      // The next save must not resurrect the bad file's path with junk.
      await mgr.save([_result('a')]);
      expect(await mgr.load(), hasLength(1));
    });

    test('a corrupt named baseline is quarantined', () async {
      final path = '${tempDir.path}/history.json';
      final mgr = HistoryManager(path);
      await mgr.saveNamedBaseline('golden', [_result('a')]);

      final baseline = File('${tempDir.path}/baselines/golden.json');
      expect(baseline.existsSync(), isTrue);
      baseline.writeAsStringSync('not json');

      expect(await mgr.loadNamedBaseline('golden'), isEmpty);
      expect(baseline.existsSync(), isFalse);
      expect(
        Directory(
          '${tempDir.path}/baselines',
        ).listSync().where((f) => f.path.contains('.corrupt-')),
        hasLength(1),
      );
    });

    test('save leaves no temporary files behind', () async {
      final path = '${tempDir.path}/history.json';
      final mgr = HistoryManager(path);
      await mgr.save([_result('a')]);
      await mgr.saveNamedBaseline('golden', [_result('a')]);

      final strays = tempDir
          .listSync(recursive: true)
          .where((e) => e.path.contains('.tmp-'))
          .toList();
      expect(strays, isEmpty);
    });

    test('save applies the per-benchmark cap', () async {
      final path = '${tempDir.path}/history.json';
      final mgr = HistoryManager(path);
      final base = DateTime.utc(2020);

      await mgr.save([
        for (var i = 0; i < 10; i++)
          _result(
            'a',
            timestamp: base.add(Duration(days: i)),
            mean: i + 1,
          ),
      ], maxEntriesPerBenchmark: 3);

      final loaded = await mgr.load();
      expect(loaded, hasLength(3));
      expect(
        loaded.map((r) => r.primary.mean),
        orderedEquals([8.0, 9.0, 10.0]),
      );
    });

    test('an existing history survives a failed save', () async {
      final path = '${tempDir.path}/history.json';
      final mgr = HistoryManager(path);
      await mgr.save([_result('a')]);
      final good = File(path).readAsStringSync();

      // Make the rename target undeletable by turning it into a non-empty
      // directory, which is the closest portable stand-in for a write that
      // fails after the temp file has been created.
      File(path).deleteSync();
      Directory(path).createSync();
      File('$path/blocker').writeAsStringSync('x');

      await mgr.save([_result('b')]); // must warn, not throw

      expect(Directory(path).existsSync(), isTrue);
      expect(File('$path/blocker').existsSync(), isTrue);
      expect(
        tempDir
            .listSync(recursive: true)
            .where((e) => e.path.contains('.tmp-')),
        isEmpty,
        reason: 'the temp file must be cleaned up when the rename fails',
      );
      expect(good, isNotEmpty);
    });
  });
}
