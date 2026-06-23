import 'dart:async';
import '../result.dart';

final class InstructionMeasurer {
  static bool get isSupported => false;

  static Future<InstructionResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
  }) async {
    return null;
  }
}
