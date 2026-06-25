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

#include <stdint.h>

#if defined(__x86_64__) || defined(_M_X64)
#ifdef _MSC_VER
#include <intrin.h>
#else
#include <x86intrin.h>
#endif

uint64_t get_cycles() {
    return __rdtsc();
}
#elif defined(__aarch64__)
uint64_t get_cycles() {
    uint64_t val;
    // Read virtual timer counter. It runs at a fixed frequency (usually 1-50MHz),
    // NOT CPU clock speed, but it is high resolution and accessible from user space.
    asm volatile("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}
#else
uint64_t get_cycles() {
    return 0; // Unsupported
}
#endif
