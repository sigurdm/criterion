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

/// High-performance statistical benchmarking framework.
library;

export 'src/criterion.dart';
export 'src/config.dart';
export 'src/result.dart';
export 'src/statistics.dart'
    show Sample, ConfidenceInterval, BootstrapResult, OutlierAnalysis;
export "src/memory_measurement.dart" show MemoryResult;
export "src/instruction_measurement.dart" show InstructionResult;
export "src/comparison.dart";
