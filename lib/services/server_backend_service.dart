import 'dart:convert';

import 'package:http/http.dart' as http;

class ServerBackendService {
  ServerBackendService._();
  static final ServerBackendService instance = ServerBackendService._();

  Future<Map<String, dynamic>> getStatus({required String baseUrl}) async {
    final uri = Uri.parse('$baseUrl/api/status');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getLatestResult({
    required String baseUrl,
  }) async {
    final uri = Uri.parse('$baseUrl/api/results/latest');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getResultById({
    required String baseUrl,
    required String runId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/results/$runId');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> getResults({
    required String baseUrl,
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/results?page=$page&page_size=$pageSize',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    final data = _decodeObject(response);
    final items = (data['items'] as List<dynamic>? ?? const []);
    return items
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<String>> getLatestLogs({
    required String baseUrl,
    int lines = 200,
  }) async {
    final uri = Uri.parse('$baseUrl/api/logs/latest?lines=$lines');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    final data = _decodeObject(response);
    final entries = (data['lines'] as List<dynamic>? ?? const []);
    return entries.map((e) => e.toString()).toList();
  }

  Future<Map<String, dynamic>> getLogsPage({
    required String baseUrl,
    int page = 1,
    int pageSize = 200,
  }) async {
    final uri = Uri.parse('$baseUrl/api/logs?page=$page&page_size=$pageSize');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    return _decodeObject(response);
  }

  Future<void> triggerRun({
    required String baseUrl,
    required String token,
    String trigger = 'api',
  }) async {
    final uri = Uri.parse('$baseUrl/internal/scheduler/run?trigger=$trigger');
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'X-Internal-Token': token,
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Run trigger failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response shape');
    }
    return decoded;
  }
}
