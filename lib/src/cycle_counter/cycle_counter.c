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

#if defined(_WIN32)
#define CRITERION_EXPORT __declspec(dllexport)
#else
#define CRITERION_EXPORT __attribute__((visibility("default")))
#endif

CRITERION_EXPORT uint64_t get_cycles(void);

#if defined(__x86_64__) || defined(_M_X64)
#ifdef _MSC_VER
#include <intrin.h>
#else
#include <x86intrin.h>
#endif

CRITERION_EXPORT uint64_t get_cycles(void) {
    unsigned int aux;
    return __rdtscp(&aux);
}
#elif defined(__aarch64__)
CRITERION_EXPORT uint64_t get_cycles(void) {
    uint64_t val;
    // Read virtual timer counter. It runs at a fixed frequency (usually 1-50MHz),
    // NOT CPU clock speed, but it is high resolution and accessible from user space.
    asm volatile("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}
#elif defined(_M_ARM64)
#include <intrin.h>

CRITERION_EXPORT uint64_t get_cycles(void) {
    // ARM64_CNTVCT = _ARM64_SYSREG(3, 3, 14, 0, 2)
    return (uint64_t)_ReadStatusReg(_ARM64_SYSREG(3, 3, 14, 0, 2));
}
#else
CRITERION_EXPORT uint64_t get_cycles(void) {
    return 0; // Unsupported
}
#endif
