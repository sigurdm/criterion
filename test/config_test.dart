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

import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  group('CriterionConfig.validate', () {
    test('accepts the defaults', () {
      expect(const CriterionConfig().validate, returnsNormally);
    });

    test('rejects out-of-range values and names the offending field', () {
      final cases = <String, CriterionConfig>{
        'kbssdWindowSize': const CriterionConfig(kbssdWindowSize: 0),
        'kbssdStabilityRequired': const CriterionConfig(
          kbssdStabilityRequired: 0,
        ),
        'kbssdTrimPercentage': const CriterionConfig(kbssdTrimPercentage: 0.5),
        'kbssdScaleFactor': const CriterionConfig(kbssdScaleFactor: 0.0),
        'kbssdMaxSamples': const CriterionConfig(
          kbssdWindowSize: 15,
          kbssdMaxSamples: 29,
        ),
        'noiseThreshold': const CriterionConfig(noiseThreshold: -0.01),
      };

      for (final entry in cases.entries) {
        expect(
          entry.value.validate,
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', entry.key),
          ),
          reason: 'expected ${entry.key} to be rejected',
        );
      }
    });

    test('accepts a trim percentage of exactly 0.0', () {
      expect(
        const CriterionConfig(kbssdTrimPercentage: 0.0).validate,
        returnsNormally,
      );
    });

    test('Criterion.run validates before running anything', () {
      final c = Criterion(
        suiteName: 'BadConfig',
        config: const CriterionConfig(kbssdWindowSize: 0),
      );
      c.bench('never runs', () => fail('benchmark should not have run'));

      expect(
        c.run(),
        throwsA(
          isA<ArgumentError>().having((e) => e.name, 'name', 'kbssdWindowSize'),
        ),
      );
    });
  });
}
