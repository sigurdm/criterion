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

import 'dart:async';
import 'package:criterion/criterion.dart';
import 'package:test/test.dart';

void main() {
  test('CycleCounter measures cycles if supported', () async {
    final config = CriterionConfig(
      generateHtmlReport: false,
      exportJson: false,
      useKbssd: false,
    );

    final prints = <String>[];
    final results = await runZoned(
      () => criterion('Cycle Test', (c) {
        c.bench(
          'simple-loop',
          () {
            var x = 0;
            for (var i = 0; i < 1000; i++) {
              x += i;
            }
            if (x == 0) throw StateError('invalid x');
          },
          samples: 5,
          warmupDuration: Duration.zero,
        );
      }, config: config),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          prints.add(line);
          parent.print(zone, line);
        },
      ),
    );

    expect(results.length, equals(1));
    final result = results.first;

    final hasCyclesPrint = prints.any((p) => p.contains('cycles:'));
    final cycles = result.primary.cyclesPerIteration;

    if (cycles != null) {
      expect(cycles, greaterThan(0));
      expect(hasCyclesPrint, isTrue);
      print('Cycles measured: $cycles');
    } else {
      print('Cycle counting not supported on this platform.');
      expect(hasCyclesPrint, isFalse);
    }
  });
}
