import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'log_service.dart';

/// Service for checking app updates from GitHub releases.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  static UpdateService get instance => _instance;

  final LogService _log = LogService.instance;

  static const String _repoOwner = 'deadman7412';
  static const String _repoName = 'bpb-automation';
  static const String _githubApiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  UpdateService._internal();

  /// Checks for updates and returns update information.
  ///
  /// Returns a map with:
  /// - 'hasUpdate': bool - whether an update is available
  /// - 'currentVersion': String - current app version
  /// - 'latestVersion': String - latest release version
  /// - 'releaseUrl': String - URL to the release page
  /// - 'releaseNotes': String - release notes/description
  /// - 'publishedAt': String - release publish date
  /// - 'assets': List<Map> - list of downloadable assets
  Future<Map<String, dynamic>> checkForUpdates() async {
    _log.logInfo('Checking for updates from GitHub releases');

    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      _log.logInfo('Current app version: $currentVersion');

      // Fetch latest release from GitHub
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _log.logWarn(
            'GitHub API returned status ${response.statusCode}: ${response.body}');
        throw Exception(
            'Failed to check for updates: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName; // Remove 'v' prefix if present

      final releaseUrl = data['html_url'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? 'No release notes available';
      final publishedAt = data['published_at'] as String? ?? '';

      // Parse assets
      final assets = (data['assets'] as List<dynamic>? ?? [])
          .map((asset) => {
                'name': asset['name'] as String? ?? '',
                'download_url': asset['browser_download_url'] as String? ?? '',
                'size': asset['size'] as int? ?? 0,
              })
          .toList();

      _log.logInfo('Latest release version: $latestVersion');
      _log.logInfo('Available assets: ${assets.length}');

      // Compare versions
      final hasUpdate = _compareVersions(currentVersion, latestVersion) < 0;

      if (hasUpdate) {
        _log.logOk('Update available: $currentVersion -> $latestVersion');
      } else {
        _log.logOk('App is up to date');
      }

      return {
        'hasUpdate': hasUpdate,
        'currentVersion': currentVersion,
        'latestVersion': latestVersion,
        'releaseUrl': releaseUrl,
        'releaseNotes': releaseNotes,
        'publishedAt': publishedAt,
        'assets': assets,
      };
    } catch (e, stackTrace) {
      _log.logError('Failed to check for updates', e, stackTrace);
      rethrow;
    }
  }

  /// Compares two semantic versions (e.g., "1.0.0").
  ///
  /// Returns:
  /// - negative if v1 < v2
  /// - zero if v1 == v2
  /// - positive if v1 > v2
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.tryParse).whereType<int>().toList();
    final parts2 = v2.split('.').map(int.tryParse).whereType<int>().toList();

    final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final part1 = i < parts1.length ? parts1[i] : 0;
      final part2 = i < parts2.length ? parts2[i] : 0;

      if (part1 != part2) {
        return part1 - part2;
      }
    }

    return 0;
  }

  /// Gets the GitHub releases page URL.
  String get releasesUrl => 'https://github.com/$_repoOwner/$_repoName/releases';

  /// Gets the GitHub repository URL.
  String get repositoryUrl => 'https://github.com/$_repoOwner/$_repoName';
}
