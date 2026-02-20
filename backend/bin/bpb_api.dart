import 'dart:io';

import 'package:bpb_autoscan_worker/api_server.dart';

Future<void> main(List<String> args) async {
  final code = await ApiServerApp().run(args);
  exit(code);
}
