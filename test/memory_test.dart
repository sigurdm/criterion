// Copyright 2026 Sigurd Meldgaard
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

class LargeObject {
  final int a;
  final int b;
  final int c;
  LargeObject(this.a, this.b, this.c);
}

List<dynamic> keeper = [];

void main() {
  group('Memory Measurement', () {
    tearDown(() {
      keeper.clear();
    });

    test('reports allocated bytes and objects close to expected', () async {
      final printLines = <String>[];

      await runZonedGuarded(
        () async {
          final c = Criterion();
          c.bench(
            'allocations',
            () {
              // Allocate a list of 100 LargeObjects
              // 1 List instance (~800 bytes) + 100 LargeObject instances (100 * 32 = 3200 bytes)
              // Total expected: ~4000 bytes per iteration
              final list = List.generate(
                100,
                (i) => LargeObject(i, i, i),
                growable: false,
              );
              keeper.add(list);
            },
            samples: 5, // Keep samples low for fast test
            warmupDuration: const Duration(milliseconds: 5),
          );
          await c.run();
        },
        (error, stack) {
          fail('Run failed with error: $error\n$stack');
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printLines.add(line);
            // Also print to parent zone so we can see it in test output if we want
            parent.print(zone, line);
          },
        ),
      );

      // Find the memory report line
      // Format: "  memory: 4.2 KB allocated (101 objects) per iteration"
      final memoryLine = printLines.firstWhere(
        (line) => line.contains('memory:'),
        orElse: () => '',
      );

      expect(
        memoryLine,
        isNotEmpty,
        reason: 'Memory report line not found in output: $printLines',
      );

      // Parse the allocated bytes
      // "  memory: X KB allocated (Y objects) per iteration"
      final match = RegExp(
        r'memory:\s+([\d\.]+)\s+(KB|B|MB)\s+allocated\s+\(([\d,\.]+)\s+objects\)',
      ).firstMatch(memoryLine);
      expect(
        match,
        isNotNull,
        reason: 'Failed to parse memory line: $memoryLine',
      );

      final value = double.parse(match!.group(1)!);
      final unit = match.group(2)!;
      final objects = double.parse(match.group(3)!.replaceAll(',', ''));

      double bytes = value;
      if (unit == 'KB') {
        bytes *= 1024;
      } else if (unit == 'MB') {
        bytes *= 1024 * 1024;
      }

      print('Parsed bytes: $bytes, objects: $objects');

      // Expected bytes: ~4000 bytes.
      // We allow some tolerance because of VM service overhead and keeper list growth.
      expect(bytes, greaterThan(3500));
      expect(bytes, lessThan(8000)); // Allow buffer for VM overhead (~1.5KB)

      // Expected objects: 101 objects (1 list + 100 LargeObjects).
      // Plus VM service overhead (~15-25 objects).
      expect(objects, greaterThanOrEqualTo(100));
      expect(objects, lessThan(140));
    });
  });
}
