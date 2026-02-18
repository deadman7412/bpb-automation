// Web-specific implementation for config download
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

/// Download configs on web platform using browser download
Future<bool> downloadConfigsOnWeb(String jsonString, String fileName) async {
  try {
    // Create blob and trigger download
    final bytes = utf8.encode(jsonString);
    final blob = html.Blob([bytes], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    // ignore: unused_local_variable
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);

    return true;
  } catch (e) {
    return false;
  }
}
