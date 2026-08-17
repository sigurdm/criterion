import 'dart:async';
import '../batch_size.dart';
import '../result.dart';

final class MemoryMeasurer {
  static Future<MemoryResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
    BatchSize? batchSize,
  }) {
    return Future.value(null);
  }
}
