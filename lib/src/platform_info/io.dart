import 'dart:io';

String get localOs => Platform.operatingSystem;
String get localDartSdkVersion => Platform.version.split(' ').first;
