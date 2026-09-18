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
import 'package:criterion/src/memory_measurement.dart';
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

    test('static sink setter and preventDCE work cleanly', () {
      expect(() => Blackhole.sink = 123, returnsNormally);
      expect(() => Blackhole.sink = 'hello', returnsNormally);
      expect(() => Blackhole.sink = null, returnsNormally);
      expect(() => Blackhole.preventDCE(), returnsNormally);
    });

    test(
      'blackbox preserves types and values across primitives, lists, objects, and nulls',
      () {
        // Primitives
        final intVal = blackbox<int>(42);
        expect(intVal, equals(42));
        expect(intVal, isA<int>());

        final doubleVal = blackbox<double>(3.14159);
        expect(doubleVal, equals(3.14159));
        expect(doubleVal, isA<double>());

        final strVal = blackbox<String>('criterion');
        expect(strVal, equals('criterion'));
        expect(strVal, isA<String>());

        final boolVal = blackbox<bool>(true);
        expect(boolVal, isTrue);
        expect(boolVal, isA<bool>());

        // Lists and collections
        final listVal = blackbox<List<int>>([1, 2, 3]);
        expect(listVal, equals([1, 2, 3]));
        expect(listVal, isA<List<int>>());

        final mapVal = blackbox<Map<String, int>>({'a': 1, 'b': 2});
        expect(mapVal, equals({'a': 1, 'b': 2}));
        expect(mapVal, isA<Map<String, int>>());

        // Custom objects
        final obj = DateTime(2026, 1, 1);
        final objVal = blackbox<DateTime>(obj);
        expect(identical(objVal, obj), isTrue);
        expect(objVal, isA<DateTime>());

        // Null values
        final nullVal = blackbox<String?>(null);
        expect(nullVal, isNull);
        expect(nullVal, isA<String?>());

        // Static method Blackhole.blackbox
        final staticVal = Blackhole.blackbox<int>(100);
        expect(staticVal, equals(100));
        expect(staticVal, isA<int>());
      },
    );

    test('blackbox does not allocate per call', () async {
      // Regression test: `blackbox` used to call `DateTime.now()` as its
      // opaque barrier, which allocated a `DateTime` and cost ~44 ns per call
      // — enough to dominate any microbenchmark it was used in.
      //
      // Measured per-iteration object counts include a small fixed VM-service
      // overhead amortized over the measurement run (~0.05 objects/iteration),
      // so a per-call allocation (1.0 objects/iteration) is far outside it.
      final result = await MemoryMeasurer.measure(
        fn: () => blackbox<int>(42),
        iterations: 500,
      );

      expect(
        result,
        isNotNull,
        reason: 'VM service unavailable; cannot verify allocation behaviour',
      );
      final objects = result!.allocatedObjectsPerIteration;
      expect(objects, isNotNull);
      expect(
        objects,
        lessThan(0.5),
        reason:
            'blackbox allocated $objects objects per call; it must not '
            'allocate on the hot path',
      );
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
