import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/run.dart <benchmark_file.dart> [extra_args...]');
    exit(1);
  }

  final targetFile = File(args.first);
  if (!targetFile.existsSync()) {
    print('Error: Target file does not exist: ${targetFile.path}');
    exit(1);
  }

  final extraArgs = args.sublist(1);

  final targetPath = targetFile.absolute.path;
  var tempExePath = targetPath;
  if (tempExePath.endsWith('.dart')) {
    tempExePath = '${tempExePath.substring(0, tempExePath.length - 5)}_aot.exe';
  } else {
    tempExePath = '${tempExePath}_aot.exe';
  }

  print('Compiling $targetPath to AOT binary...');
  final dartPath = Platform.resolvedExecutable;

  final compileResult = await Process.run(dartPath, [
    'compile',
    'exe',
    targetPath,
    '-o',
    tempExePath,
  ]);

  if (compileResult.exitCode != 0) {
    print('Compilation failed with exit code ${compileResult.exitCode}');
    print(compileResult.stdout);
    print(compileResult.stderr);
    exit(compileResult.exitCode);
  }

  print('Executing compiled binary: $tempExePath');
  final process = await Process.start(
    tempExePath,
    extraArgs,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;

  // Cleanup
  try {
    final tempExeFile = File(tempExePath);
    if (tempExeFile.existsSync()) {
      tempExeFile.deleteSync();
    }
  } catch (e) {
    print('Warning: Failed to delete temporary binary $tempExePath: $e');
  }

  exit(exitCode);
}
