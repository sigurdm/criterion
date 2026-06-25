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

class MyTestClass {
  final int value;
  MyTestClass(this.value);
}

void main() {
  test('detailed memory profiling reports class allocations', () async {
    final config = CriterionConfig(
      generateHtmlReport: false,
      exportJson: false,
      useKbssd: false,
    );

    final prints = <String>[];
    final results = await runZoned(
      () => criterion('Memory Profile Test', (c) {
        c.bench(
          'allocate-custom',
          () {
            final list = List.generate(100, (i) => MyTestClass(i));
            var sum = 0;
            for (final obj in list) {
              sum += obj.value;
            }
            if (sum == 0) throw StateError('invalid sum');
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
    expect(result.primary.memory, isNotNull);
    final memory = result.primary.memory!;
    expect(memory.classAllocations, isNotNull);

    final hasMyTestClass = memory.classAllocations!.any(
      (c) => c.className == 'MyTestClass' && (c.bytes > 0 || c.instances > 0),
    );
    expect(
      hasMyTestClass,
      isTrue,
      reason: 'Expected MyTestClass in allocations: ${memory.classAllocations}',
    );

    final hasTopAllocationsPrint = prints.any(
      (p) => p.contains('Top allocations:'),
    );
    expect(hasTopAllocationsPrint, isTrue);
    final hasMyTestClassPrint = prints.any((p) => p.contains('MyTestClass'));
    expect(hasMyTestClassPrint, isTrue);
  });
}
