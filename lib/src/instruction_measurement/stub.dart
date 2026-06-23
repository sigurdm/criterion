import "../result.dart";

final class InstructionMeasurer {
  static bool get isSupported => false;

  static InstructionResult? measure({
    required void Function() fn,
    required int iterations,
  }) {
    return null;
  }
}
