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

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as dart_isolate;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import '../result.dart';

/// Helper to collect CPU profiles using the VM Service.
final class CpuProfiler {
  /// Collects CPU samples during execution of [fn].
  static Future<CpuProfileResult?> collect({
    required Function fn,
    required int iterations,
    Function? setup,
    String? exportPath,
  }) async {
    VmService? service;
    try {
      final info = await developer.Service.controlWebServer(enable: true);
      final uri = info.serverUri;
      if (uri == null) return null;
      final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
      service = await vmServiceConnectUri(wsUri.toString());

      final isolateId = developer.Service.getIsolateId(
        dart_isolate.Isolate.current,
      );
      if (isolateId == null) return null;

      // Enable profiler if disabled
      try {
        final flagList = await service.getFlagList();
        for (final flag in flagList.flags ?? <Flag>[]) {
          if (flag.name == 'profiler' && flag.valueAsString == 'false') {
            await service.setFlag('profiler', 'true');
          }
        }
      } catch (_) {
        // Ignore
      }

      final states = <dynamic>[];
      if (setup != null) {
        for (var i = 0; i < iterations; i++) {
          final state = setup();
          states.add(state is Future ? await state : state);
        }
      }

      final startTime = (await service.getVMTimelineMicros()).timestamp!;

      for (var i = 0; i < iterations; i++) {
        if (setup != null) {
          final r = fn(states[i]);
          if (r is Future) await r;
        } else {
          final r = fn();
          if (r is Future) await r;
        }
      }

      final endTime = (await service.getVMTimelineMicros()).timestamp!;

      final cpuSamples = await service.getCpuSamples(
        isolateId,
        startTime,
        endTime - startTime,
      );

      if (exportPath != null) {
        try {
          final file = File(exportPath);
          if (!file.parent.existsSync()) {
            file.parent.createSync(recursive: true);
          }
          file.writeAsStringSync(jsonEncode(cpuSamples.toJson()));
        } catch (e) {
          stderr.writeln(
            'Warning: Failed to export CPU profile to $exportPath: $e',
          );
        }
      }

      final functions = <CpuProfileFunction>[];
      for (final f in cpuSamples.functions ?? <ProfileFunction>[]) {
        if ((f.inclusiveTicks ?? 0) > 0 || (f.exclusiveTicks ?? 0) > 0) {
          String funcName = 'Unknown';
          final func = f.function;
          if (func is FuncRef) {
            funcName = func.name ?? 'Unknown';
          } else if (func is Map) {
            final parsed = FuncRef.parse(func.cast<String, dynamic>());
            funcName = parsed?.name ?? 'Unknown';
          } else if (func != null) {
            funcName = func.toString();
          }

          functions.add(
            CpuProfileFunction(
              name: funcName,
              resolvedUrl: f.resolvedUrl ?? 'Unknown',
              inclusiveTicks: f.inclusiveTicks ?? 0,
              exclusiveTicks: f.exclusiveTicks ?? 0,
            ),
          );
        }
      }

      return CpuProfileResult(
        functions: functions,
        sampleCount: cpuSamples.sampleCount ?? 0,
        samplePeriod: cpuSamples.samplePeriod ?? 0,
      );
    } catch (e) {
      return null;
    } finally {
      if (service != null) {
        await service.dispose();
      }
    }
  }
}
