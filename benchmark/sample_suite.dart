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

import 'dart:ffi';
import 'package:criterion/criterion.dart';
import 'package:ffi/ffi.dart';

int labsDart(int n) => n < 0 ? -n : n;

@Native<Int64 Function(Int64)>(symbol: 'labs')
external int labsNonLeaf(int j);

@Native<Int64 Function(Int64)>(symbol: 'labs', isLeaf: true)
external int labsLeaf(int j);

@Native<UintPtr Function(Pointer<Char>)>(symbol: 'strlen', isLeaf: true)
external int strlenLeaf(Pointer<Char> s);

int fib(int n) {
  if (n <= 1) return n;
  return fib(n - 1) + fib(n - 2);
}

int fibIterative(int n) {
  if (n <= 1) return n;
  var a = 0;
  var b = 1;
  for (var i = 2; i <= n; i++) {
    final temp = a + b;
    a = b;
    b = temp;
  }
  return b;
}

void main() async {
  final str1000 = ('a' * 1000).toNativeUtf8();
  final strEmpty = ''.toNativeUtf8();

  try {
    await criterion('Sample Suite', (c) {
      c.group('Fibonacci', () {
        c.bench('Recursive', () => fib(20));
        c.bench('Iterative', () => fibIterative(20));
      });

      c.group('String Concatenation', () {
        c.bench('operator +', () {
          var s = '';
          for (var i = 0; i < 100; i++) {
            s += 'a';
          }
          if (s.isEmpty) throw StateError('must not be empty');
        });
        c.bench('StringBuffer', () {
          final sb = StringBuffer();
          for (var i = 0; i < 100; i++) {
            sb.write('a');
          }
          final s = sb.toString();
          if (s.isEmpty) throw StateError('must not be empty');
        });
      });

      c.group('FFI Labs', () {
        c.bench('labs (Dart)', () => labsDart(-100));
        c.bench('labs (FFI Leaf)', () => labsLeaf(-100));
        c.bench('labs (FFI Non-Leaf)', () => labsNonLeaf(-100));
      });

      c.bench(
        'strlen (1000 chars)',
        () {
          strlenLeaf(str1000.cast<Char>());
        },
        noOp: () {
          strlenLeaf(strEmpty.cast<Char>());
        },
      );
    });
  } finally {
    calloc.free(str1000);
    calloc.free(strEmpty);
  }
}
