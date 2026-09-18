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
import 'package:criterion/src/instruction_measurement.dart';
import 'package:test/test.dart';

void main() {
  group('Instruction Measurement', () {
    test('measure works or returns null depending on support', () async {
      final result = await InstructionMeasurer.measure(
        fn: () {
          var s = 0;
          for (var i = 0; i < 1000; i++) {
            s += i;
          }
          if (s == 0) throw StateError('invalid s');
        },
        iterations: 100,
      );
      if (InstructionMeasurer.isSupported) {
        expect(result, isNotNull);
        expect(result!.instructionsPerIteration, greaterThan(0.0));
      } else {
        expect(result, isNull);
      }
    });

    test('isSupported matches host capability', () {
      final supported = InstructionMeasurer.isSupported;
      expect(supported, isA<bool>());
      if (!Platform.isLinux) {
        expect(supported, isFalse);
      }
    });
  });
}
