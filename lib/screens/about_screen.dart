import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../widgets/logs_action_button.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final UpdateService _updateService = UpdateService.instance;

  String _appVersion = 'Loading...';
  String _buildNumber = '';
  bool _checkingForUpdates = false;
  String? _updateStatus;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Unknown';
        _buildNumber = '';
      });
    }
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not launch $url'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingForUpdates = true;
      _updateStatus = null;
    });

    try {
      final updateInfo = await _updateService.checkForUpdates();

      if (!mounted) return;

      if (updateInfo['hasUpdate'] == true) {
        final latestVersion = updateInfo['latestVersion'] as String;
        setState(() {
          _updateStatus = 'Update available: v$latestVersion';
        });

        // Show update dialog
        _showUpdateDialog(updateInfo);
      } else {
        setState(() {
          _updateStatus = 'You are on the latest version';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are already running the latest version'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _updateStatus = 'Failed to check for updates';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to check for updates: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdates = false;
        });
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateInfo) {
    final latestVersion = updateInfo['latestVersion'] as String;
    final releaseUrl = updateInfo['releaseUrl'] as String;
    final releaseNotes = updateInfo['releaseNotes'] as String;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version $latestVersion is now available!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Current version: $_appVersion',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text(
                'Release Notes:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                releaseNotes.length > 300
                    ? '${releaseNotes.substring(0, 300)}...'
                    : releaseNotes,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchURL(releaseUrl);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: const [LogsActionButton(currentRoute: '/about')],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App Icon and Name
              const Icon(Icons.cloud_sync, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'BPB Automation',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Version $_appVersion${_buildNumber.isNotEmpty ? ' ($_buildNumber)' : ''}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Description
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'BPB Automation is a helper app for handling clean IP scan/update workflows for BPB Panel.\n\n'
                        'This app is designed specifically for BPB Worker Panel and is not a general-purpose panel manager.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Compatibility Notice
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.verified,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Compatibility',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Only works with BPB Worker Panel created by bia-pain-bache.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text:
                                  'github.com/bia-pain-bache/BPB-Worker-Panel/tree/main',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _launchURL(
                                  'https://github.com/bia-pain-bache/BPB-Worker-Panel/tree/main',
                                ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Creator Info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Creator',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.person, size: 20, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('deadman7412'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // GitHub Repository
              Card(
                child: InkWell(
                  onTap: () => _launchURL(
                    'https://github.com/deadman7412/bpb-automation',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.code, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'GitHub Repository',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyMedium,
                            children: [
                              TextSpan(
                                text: 'github.com/deadman7412/bpb-automation',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _launchURL(
                                    'https://github.com/deadman7412/bpb-automation',
                                  ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'View source code, report issues, and contribute',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Check for Updates
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.system_update, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Updates',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_updateStatus != null) ...[
                        Text(
                          _updateStatus!,
                          style: TextStyle(
                            color: _updateStatus!.contains('available')
                                ? Colors.orange
                                : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: _checkingForUpdates
                            ? null
                            : _checkForUpdates,
                        icon: _checkingForUpdates
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _checkingForUpdates
                              ? 'Checking...'
                              : 'Check for Updates',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Releases Link
              Card(
                child: InkWell(
                  onTap: () => _launchURL(
                    'https://github.com/deadman7412/bpb-automation/releases',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.download, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Releases',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyMedium,
                            children: [
                              TextSpan(
                                text:
                                    'github.com/deadman7412/bpb-automation/releases',
                                style: const TextStyle(
                                  color: Colors.green,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _launchURL(
                                    'https://github.com/deadman7412/bpb-automation/releases',
                                  ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Download latest releases and view changelog',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // License & copyright
              Text(
                '© 2025 deadman7412',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Open-source under the MIT License.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
