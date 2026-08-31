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
  group('BatchSize', () {
    test('numIterations validation', () {
      expect(() => BatchSize.numIterations(0), throwsArgumentError);
      expect(() => BatchSize.numIterations(-5), throwsArgumentError);
      final custom = BatchSize.numIterations(50);
      expect(custom.batchSizeFor(120), equals(50));
      expect(custom.batchSizeFor(30), equals(30));
    });

    test('fixed batch size methods and equality', () {
      final b1 = BatchSize.smallInput;
      final b2 = BatchSize.numIterations(1000);
      final b3 = BatchSize.largeInput;

      expect(b1.batchSizeFor(5000), equals(1000));
      expect(b1.batchSizeFor(250), equals(250));

      expect(b1, equals(b2));
      expect(b1.hashCode, equals(b2.hashCode));
      expect(b1, isNot(equals(b3)));
      expect(b3, equals(BatchSize.perIteration));
      expect(b3.hashCode, equals(BatchSize.perIteration.hashCode));
      expect(b1, isNot(equals(BatchSize.unbatched)));

      expect(b1.toString(), equals('BatchSize.smallInput'));
      expect(b3.toString(), equals('BatchSize.largeInput'));
      expect(
        BatchSize.perIteration.toString(),
        equals('BatchSize.perIteration'),
      );
      expect(
        BatchSize.numIterations(42).toString(),
        equals('BatchSize.numIterations(42)'),
      );
    });

    test('unbatched methods and equality', () {
      final u1 = BatchSize.unbatched;
      final u2 = BatchSize.all;

      expect(u1.batchSizeFor(500), equals(500));
      expect(u1, equals(u2));
      expect(u1.hashCode, equals(u2.hashCode));
      expect(u1, isNot(equals(BatchSize.smallInput)));

      expect(u1.toString(), equals('BatchSize.unbatched'));
      expect(u2.toString(), equals('BatchSize.all'));
    });
  });
}
