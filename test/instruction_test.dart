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

import 'package:criterion/src/instruction_measurement.dart';
import 'package:test/test.dart';

void main() {
  group('Instruction Measurement', () {
    test('measure works or returns null depending on support', () {
      final result = InstructionMeasurer.measure(fn: () {}, iterations: 100);
      if (InstructionMeasurer.isSupported) {
        expect(result, isNotNull);
        expect(result!.instructionsPerIteration, greaterThanOrEqualTo(0.0));
      } else {
        expect(result, isNull);
      }
    });

    test('isSupported matches host capability', () {
      // Just verifying we can call it without throwing.
      final supported = InstructionMeasurer.isSupported;
      print('Instruction measurer supported on this host: $supported');
    });
  });
}
