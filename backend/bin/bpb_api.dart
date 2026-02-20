import 'dart:io';

import '../lib/api_server.dart';

Future<void> main(List<String> args) async {
  final code = await ApiServerApp().run(args);
  exit(code);
}
