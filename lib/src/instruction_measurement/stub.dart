import 'dart:async';
import '../batch_size.dart';
import '../result.dart';

final class InstructionMeasurer {
  static bool get isSupported => false;

  static Future<InstructionResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    BatchSize? batchSize,
  }) async {
    return null;
  }
}
