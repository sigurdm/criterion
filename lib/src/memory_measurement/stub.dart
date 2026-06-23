import 'dart:async';
import '../result.dart';

final class MemoryMeasurer {
  static Future<MemoryResult?> measure({
    required Function fn,
    required int iterations,
    Function? setup,
  }) {
    return Future.value(null);
  }
}
