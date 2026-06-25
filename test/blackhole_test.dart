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
  group('Blackhole', () {
    test('can consume values', () {
      final bh = Blackhole();
      expect(() => bh.consume(42), returnsNormally);
      expect(() => bh.consume('string'), returnsNormally);
      expect(() => bh.consume(null), returnsNormally);
    });

    test('global blackhole function can consume values', () {
      expect(() => blackhole(42), returnsNormally);
      expect(() => blackhole('string'), returnsNormally);
      expect(() => blackhole(null), returnsNormally);
    });

    test('harness integration works', () async {
      final c = Criterion();
      c.bench(
        'bench_with_blackhole',
        () {
          final value = _expensiveComputation();
          blackhole(value);
        },
        samples: 5,
        warmupDuration: const Duration(milliseconds: 5),
      );

      final results = await c.run();
      expect(results.length, equals(1));
    });
  });
}

int _expensiveComputation() {
  var sum = 0;
  for (var i = 0; i < 100; i++) {
    sum += i;
  }
  return sum;
}
