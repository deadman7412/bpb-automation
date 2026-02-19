import 'package:flutter/material.dart';
import '../models/credentials.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/log_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiTokenController = TextEditingController();
  final _accountIdController = TextEditingController();
  final _kvNamespaceIdController = TextEditingController();

  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;
  final LogService _log = LogService.instance;

  bool _isLoading = false;
  bool _isValidating = false;
  bool _obscureToken = true;
  bool _hasCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _accountIdController.dispose();
    _kvNamespaceIdController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    _log.logInfo('SettingsScreen: Loading credentials on startup');
    setState(() => _isLoading = true);

    final credentials = await _storage.getCredentials();

    if (credentials != null) {
      _log.logOk('SettingsScreen: Credentials found, populating fields');
      _log.logInfo('  API Token length: ${credentials.apiToken.length}');
      _log.logInfo('  Account ID: ${credentials.accountId}');
      _log.logInfo('  KV Namespace ID: ${credentials.kvNamespaceId}');

      _apiTokenController.text = credentials.apiToken;
      _accountIdController.text = credentials.accountId;
      _kvNamespaceIdController.text = credentials.kvNamespaceId;
      setState(() => _hasCredentials = true);
    } else {
      _log.logWarn('SettingsScreen: No credentials found in storage');
    }

    setState(() => _isLoading = false);
    _log.logInfo('SettingsScreen: Finished loading credentials');
  }

  Future<void> _saveCredentials() async {
    _log.logInfo('SettingsScreen: Save button pressed');

    if (!_formKey.currentState!.validate()) {
      _log.logWarn('SettingsScreen: Form validation failed');
      return;
    }

    setState(() => _isLoading = true);

    final credentials = Credentials(
      apiToken: _apiTokenController.text.trim(),
      accountId: _accountIdController.text.trim(),
      kvNamespaceId: _kvNamespaceIdController.text.trim(),
    );

    _log.logInfo('SettingsScreen: Calling storage.saveCredentials()');
    await _storage.saveCredentials(credentials);
    _log.logOk('SettingsScreen: Credentials saved successfully');

    setState(() {
      _isLoading = false;
      _hasCredentials = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Credentials saved successfully'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _validateCredentials() async {
    _log.logInfo('SettingsScreen: Validate button pressed');

    if (!_formKey.currentState!.validate()) {
      _log.logWarn('SettingsScreen: Form validation failed');
      return;
    }

    setState(() => _isValidating = true);

    final credentials = Credentials(
      apiToken: _apiTokenController.text.trim(),
      accountId: _accountIdController.text.trim(),
      kvNamespaceId: _kvNamespaceIdController.text.trim(),
    );

    _log.logInfo('SettingsScreen: Calling API to validate credentials');
    final isValid = await _api.validateCredentials(credentials);
    _log.logInfo('SettingsScreen: Validation result: $isValid');

    setState(() => _isValidating = false);

    if (!mounted) return;

    if (isValid) {
      _log.logOk('SettingsScreen: Credentials validated successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credentials validated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _log.logOk('Credentials validated successfully');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid credentials. Please check and try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _log.logWarn('Credential validation failed');
    }
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Credentials'),
        content: const Text(
          'Are you sure you want to clear all saved credentials?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.clearCredentials();
      _apiTokenController.clear();
      _accountIdController.clear();
      _kvNamespaceIdController.clear();

      setState(() => _hasCredentials = false);

      _log.logInfo('Credentials cleared');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credentials cleared'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'BPB Automation',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.cloud_sync, size: 64),
      children: [
        const SizedBox(height: 16),
        const Text(
          'Cross-platform automation tool for finding and updating clean Cloudflare IPs in BPB Panel.',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        const Text(
          'Features:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('- Scan for clean Cloudflare IPs'),
        const Text('- Automatic BPB Panel updates'),
        const Text('- No credentials needed for scanning'),
        const Text('- Secure credential storage'),
        const Text('- Cross-platform support'),
        const SizedBox(height: 16),
        const Text(
          'Credits:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('Scanner: Cloudflare-Clean-IP-Scanner'),
        const Text('Panel: BPB-Worker-Panel'),
        const SizedBox(height: 16),
        const Text(
          'Need Help?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('Check the Logs screen for troubleshooting'),
        const Text('View scan results for IP statistics'),
        const Text('Configure scanner in Config screen'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug & Diagnostics',
            onPressed: () => Navigator.pushNamed(context, '/debug'),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'About & Help',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cloudflare Credentials',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your Cloudflare API credentials to enable automatic IP updates.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                      const SizedBox(height: 24),

                      // API Token Field
                      TextFormField(
                        controller: _apiTokenController,
                        decoration: InputDecoration(
                          labelText: 'API Token',
                          hintText: 'Enter your Cloudflare API token',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.vpn_key),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureToken
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() => _obscureToken = !_obscureToken);
                            },
                          ),
                          helperText: 'Workers KV API token with edit permissions',
                        ),
                        obscureText: _obscureToken,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'API token is required';
                          }
                          if (value.trim().length < 10) {
                            return 'API token is too short';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Account ID Field
                      TextFormField(
                        controller: _accountIdController,
                        decoration: const InputDecoration(
                          labelText: 'Account ID',
                          hintText: 'Enter your Cloudflare account ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_circle),
                          helperText: 'Found in Cloudflare dashboard',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Account ID is required';
                          }
                          if (value.trim().length < 10) {
                            return 'Account ID appears to be too short';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // KV Namespace ID Field
                      TextFormField(
                        controller: _kvNamespaceIdController,
                        decoration: const InputDecoration(
                          labelText: 'KV Namespace ID',
                          hintText: 'Enter your KV namespace ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.storage),
                          helperText: 'Workers KV namespace containing proxySettings',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'KV Namespace ID is required';
                          }
                          if (value.trim().length < 10) {
                            return 'KV Namespace ID appears to be too short';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Help Section
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How to get credentials',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '1. Create API token with Workers KV Storage edit permission\n'
                                '2. Copy Account ID from Cloudflare dashboard\n'
                                '3. Copy KV Namespace ID from Storage & databases > Workers KV\n'
                                '4. Enter credentials above and click Validate\n'
                                '5. Click Save to store credentials securely',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isValidating ? null : _validateCredentials,
                              icon: _isValidating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(_isValidating ? 'Validating...' : 'Validate'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saveCredentials,
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_hasCredentials) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _clearCredentials,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear Credentials'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
