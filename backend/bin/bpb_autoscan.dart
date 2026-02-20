// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import '../lib/worker_app.dart';

Future<void> main(List<String> args) async {
  final app = WorkerApp();
  final code = await app.run(args);
  exit(code);
}
