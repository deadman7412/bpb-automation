import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/credentials.dart';
import '../models/panel_credentials.dart';
import '../models/update_mode.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/panel_api_service.dart';
import '../services/log_service.dart';
import '../widgets/logs_action_button.dart';

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
  final _panelBaseUrlController = TextEditingController();
  final _panelPasswordController = TextEditingController();

  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;
  final PanelApiService _panelApi = PanelApiService.instance;
  final LogService _log = LogService.instance;

  bool _isLoading = false;
  bool _isValidating = false;
  bool _obscureToken = true;
  bool _obscurePanelPassword = true;
  bool _isNormalizingPanelUrl = false;
  bool _hasCredentials = false;
  bool _autoApplyAfterScan = false;
  UpdateMode _updateMode = UpdateMode.panelApi;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiTokenController.dispose();
    _accountIdController.dispose();
    _kvNamespaceIdController.dispose();
    _panelBaseUrlController.dispose();
    _panelPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _log.logInfo('SettingsScreen: Loading settings on startup');
    setState(() => _isLoading = true);

    final mode = await _storage.getUpdateMode();
    final credentials = await _storage.getCredentials();
    final panelCredentials = await _storage.getPanelCredentials();
    final autoApplyAfterScan = await _storage.getAutoApplyAfterScan();

    _updateMode = mode;

    if (credentials != null) {
      _apiTokenController.text = credentials.apiToken;
      _accountIdController.text = credentials.accountId;
      _kvNamespaceIdController.text = credentials.kvNamespaceId;
    }

    if (panelCredentials != null) {
      _panelBaseUrlController.text = panelCredentials.baseUrl;
      _panelPasswordController.text = panelCredentials.password;
    }

    setState(() {
      _hasCredentials = _hasCredentialsForMode(_updateMode);
      _autoApplyAfterScan = autoApplyAfterScan;
      _isLoading = false;
    });

    _log.logInfo('SettingsScreen: Finished loading settings');
  }

  bool _hasCredentialsForMode(UpdateMode mode) {
    if (mode == UpdateMode.cloudflareApi) {
      return _apiTokenController.text.trim().isNotEmpty &&
          _accountIdController.text.trim().isNotEmpty &&
          _kvNamespaceIdController.text.trim().isNotEmpty;
    }

    return _panelBaseUrlController.text.trim().isNotEmpty &&
        _panelPasswordController.text.trim().isNotEmpty;
  }

  String _normalizePanelBaseUrl(String rawInput) {
    final raw = rawInput.trim();
    if (raw.isEmpty) return raw;

    Uri uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      return raw;
    }

    if (!uri.hasScheme || uri.host.isEmpty) {
      return raw;
    }

    final isPanelPath = uri.path == '/panel' || uri.path.startsWith('/panel/');
    final normalizedPath = isPanelPath ? '' : uri.path;

    final normalized = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: normalizedPath,
    ).toString();

    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  void _normalizePanelBaseUrlField() {
    if (_isNormalizingPanelUrl) return;

    final current = _panelBaseUrlController.text;
    final normalized = _normalizePanelBaseUrl(current);
    if (normalized == current) return;

    _isNormalizingPanelUrl = true;
    _panelBaseUrlController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    _isNormalizingPanelUrl = false;
  }

  Future<void> _saveCurrentCredentials() async {
    _log.logInfo('SettingsScreen: Save button pressed');

    if (!_formKey.currentState!.validate()) {
      _log.logWarn('SettingsScreen: Form validation failed');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? autoSubscriptionUrl;
      bool autoPopulateFailed = false;
      Object? autoPopulateError;

      if (_updateMode == UpdateMode.cloudflareApi) {
        final credentials = Credentials(
          apiToken: _apiTokenController.text.trim(),
          accountId: _accountIdController.text.trim(),
          kvNamespaceId: _kvNamespaceIdController.text.trim(),
        );
        await _storage.saveCredentials(credentials);
      } else {
        _normalizePanelBaseUrlField();
        final credentials = PanelCredentials(
          baseUrl: _normalizePanelBaseUrl(_panelBaseUrlController.text),
          password: _panelPasswordController.text.trim(),
        );
        await _storage.savePanelCredentials(credentials);

        try {
          autoSubscriptionUrl = await _panelApi.fetchNormalSubscriptionUrl(
            credentials,
          );
          if (autoSubscriptionUrl != null && autoSubscriptionUrl.isNotEmpty) {
            await _storage.saveSubscriptionUrl(autoSubscriptionUrl);
            _log.logOk(
              'Auto-populated subscription URL from panel API settings',
            );
          }
        } catch (e, stackTrace) {
          autoPopulateFailed = true;
          autoPopulateError = e;
          _log.logWarn(
            'Panel credentials were saved, but auto-populating subscription URL failed: $e',
          );
          _log.logError(
            'Auto-populate subscription URL failure',
            e,
            stackTrace,
          );
        }
      }

      await _storage.saveUpdateMode(_updateMode);
      await _storage.saveAutoApplyAfterScan(_autoApplyAfterScan);

      setState(() {
        _isLoading = false;
        _hasCredentials = true;
      });

      if (!mounted) return;
      final isPanelMode = _updateMode == UpdateMode.panelApi;
      final suggestCloudflare =
          autoPopulateError != null &&
          _panelApi.isConnectivityError(autoPopulateError);
      final panelMessage = autoSubscriptionUrl != null
          ? 'Panel API settings saved. Subscription URL auto-populated.'
          : suggestCloudflare
          ? 'Panel API settings saved, but panel domain is unreachable right now. Switch Update Method to Cloudflare API and retry.'
          : autoPopulateFailed
          ? 'Panel API settings saved. Subscription URL auto-populate failed.'
          : 'Panel API settings saved. Subscription URL not available from panel.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _updateMode == UpdateMode.cloudflareApi
                ? 'Cloudflare settings saved successfully'
                : panelMessage,
          ),
          backgroundColor: isPanelMode && autoSubscriptionUrl == null
              ? Colors.orange
              : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _validateCurrentCredentials() async {
    _log.logInfo('SettingsScreen: Validate button pressed');

    if (!_formKey.currentState!.validate()) {
      _log.logWarn('SettingsScreen: Form validation failed');
      return;
    }

    setState(() => _isValidating = true);

    bool isValid;
    Object? panelValidationError;
    if (_updateMode == UpdateMode.cloudflareApi) {
      final credentials = Credentials(
        apiToken: _apiTokenController.text.trim(),
        accountId: _accountIdController.text.trim(),
        kvNamespaceId: _kvNamespaceIdController.text.trim(),
      );
      isValid = await _api.validateCredentials(credentials);
    } else {
      _normalizePanelBaseUrlField();
      final credentials = PanelCredentials(
        baseUrl: _normalizePanelBaseUrl(_panelBaseUrlController.text),
        password: _panelPasswordController.text.trim(),
      );
      try {
        await _panelApi.verifyCredentials(credentials);
        isValid = true;
      } catch (e, stackTrace) {
        panelValidationError = e;
        isValid = false;
        _log.logError('Failed to validate panel credentials', e, stackTrace);
      }
    }

    setState(() => _isValidating = false);

    if (!mounted) return;

    final panelConnectivityIssue =
        _updateMode == UpdateMode.panelApi &&
        panelValidationError != null &&
        _panelApi.isConnectivityError(panelValidationError);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isValid
              ? 'Credentials validated successfully'
              : panelConnectivityIssue
              ? 'Could not reach the panel domain. Network may be disturbed. Switch Update Method to Cloudflare API and try again.'
              : 'Invalid credentials. Please check and try again.',
        ),
        backgroundColor: isValid
            ? Colors.green
            : panelConnectivityIssue
            ? Colors.orange
            : Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearCurrentCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Credentials'),
        content: Text(
          _updateMode == UpdateMode.cloudflareApi
              ? 'Clear saved Cloudflare API credentials?'
              : 'Clear saved Panel API credentials?',
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

    if (confirmed != true) return;

    if (_updateMode == UpdateMode.cloudflareApi) {
      await _storage.clearCredentials();
      _apiTokenController.clear();
      _accountIdController.clear();
      _kvNamespaceIdController.clear();
    } else {
      await _storage.clearPanelCredentials();
      _panelBaseUrlController.clear();
      _panelPasswordController.clear();
      _panelApi.clearSession();
    }

    setState(() => _hasCredentials = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Credentials cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildUpdateModeSelector() {
    return DropdownButtonFormField<UpdateMode>(
      initialValue: _updateMode,
      decoration: const InputDecoration(
        labelText: 'Update Method',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.sync_alt),
      ),
      items: UpdateMode.values
          .map(
            (mode) => DropdownMenuItem<UpdateMode>(
              value: mode,
              child: Text(mode.displayName),
            ),
          )
          .toList(),
      onChanged: (value) async {
        if (value == null) return;
        setState(() {
          _updateMode = value;
          _hasCredentials = _hasCredentialsForMode(value);
        });
        await _storage.saveUpdateMode(value);
      },
    );
  }

  Widget _buildCloudflareForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cloudflare API Credentials',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Use direct Workers KV API updates (recommended for web compatibility).',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text(
          'After each update, allow up to 60 seconds for new configs to take effect.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _apiTokenController,
          decoration: InputDecoration(
            labelText: 'API Token',
            hintText: 'Enter your Cloudflare API token',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.vpn_key),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureToken ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() => _obscureToken = !_obscureToken);
              },
            ),
            helperText: 'Workers KV API token with edit permissions',
          ),
          obscureText: _obscureToken,
          validator: (value) {
            if (_updateMode != UpdateMode.cloudflareApi) return null;
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
            if (_updateMode != UpdateMode.cloudflareApi) return null;
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
            if (_updateMode != UpdateMode.cloudflareApi) return null;
            if (value == null || value.trim().isEmpty) {
              return 'KV Namespace ID is required';
            }
            if (value.trim().length < 10) {
              return 'KV Namespace ID appears to be too short';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPanelApiForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Panel API Credentials',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Use BPB panel login + update endpoints (/login/authenticate, /panel/update-settings).',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text(
          'If your network is disturbed or panel is only reachable via VPN, use Cloudflare API mode instead.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _panelBaseUrlController,
          decoration: const InputDecoration(
            labelText: 'Panel Base URL',
            hintText: 'https://your-worker.workers.dev',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
            helperText:
                'Use root URL only. If you paste /panel, it is auto-removed.',
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => _normalizePanelBaseUrlField(),
          validator: (value) {
            if (_updateMode != UpdateMode.panelApi) return null;
            final raw = _normalizePanelBaseUrl(value?.trim() ?? '');
            if (raw.isEmpty) {
              return 'Panel base URL is required';
            }
            Uri? uri;
            try {
              uri = Uri.parse(raw);
            } catch (_) {
              uri = null;
            }
            if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
              return 'Enter a valid absolute URL';
            }
            if (uri.path.isNotEmpty && uri.path != '/') {
              return 'Do not include a path (use root URL)';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _panelPasswordController,
          decoration: InputDecoration(
            labelText: 'Panel Password',
            hintText: 'Enter panel password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePanelPassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() {
                  _obscurePanelPassword = !_obscurePanelPassword;
                });
              },
            ),
          ),
          obscureText: _obscurePanelPassword,
          validator: (value) {
            if (_updateMode != UpdateMode.panelApi) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Panel password is required';
            }
            return null;
          },
        ),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Web builds may fail with panel API due to browser CORS/cookie restrictions. Use Cloudflare API mode if this happens.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          const LogsActionButton(),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug & Diagnostics',
            onPressed: () => Navigator.pushNamed(context, '/debug'),
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
                      _buildUpdateModeSelector(),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto apply after scan'),
                        subtitle: Text(
                          'Automatically update BPB using ${_updateMode.displayName} when a scan finishes with working IPs.',
                        ),
                        value: _autoApplyAfterScan,
                        onChanged: (value) {
                          setState(() => _autoApplyAfterScan = value);
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_updateMode == UpdateMode.cloudflareApi)
                        _buildCloudflareForm()
                      else
                        _buildPanelApiForm(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isValidating
                                  ? null
                                  : _validateCurrentCredentials,
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
                              label: Text(
                                _isValidating ? 'Validating...' : 'Validate',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saveCurrentCredentials,
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
                          onPressed: _clearCurrentCredentials,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _updateMode == UpdateMode.cloudflareApi
                                ? 'Clear Cloudflare Credentials'
                                : 'Clear Panel Credentials',
                          ),
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
