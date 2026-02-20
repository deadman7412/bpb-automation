import 'dart:io';

import 'package:bpb_autoscan_worker/worker_app.dart';

Future<void> main(List<String> args) async {
  final app = WorkerApp();
  final code = await app.run(args);
  exit(code);
}
