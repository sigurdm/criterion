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
