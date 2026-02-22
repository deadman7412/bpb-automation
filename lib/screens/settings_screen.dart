import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/credentials.dart';
import '../models/panel_credentials.dart';
import '../models/update_mode.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/panel_api_service.dart';
import '../services/server_backend_service.dart';
import '../services/log_service.dart';
import '../widgets/experimental_server_banner.dart';
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
  final _serverBaseUrlController = TextEditingController();
  final _serverTokenController = TextEditingController();
  final _serverUsernameController = TextEditingController();
  final _serverPasswordController = TextEditingController();
  final _panelDohUrlOverrideController = TextEditingController();

  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;
  final PanelApiService _panelApi = PanelApiService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;
  final LogService _log = LogService.instance;

  bool _isLoading = false;
  bool _isValidating = false;
  bool _obscureToken = true;
  bool _obscurePanelPassword = true;
  bool _obscureServerToken = true;
  bool _obscureServerPassword = true;
  bool _isNormalizingPanelUrl = false;
  bool _isServerSigningIn = false;
  bool _hasCredentials = false;
  bool _autoApplyAfterScan = false;
  bool _cloudflareTryEchViaProxy = false;
  bool _cloudflareTryEchViaDirectResolvers = true;
  bool _cloudflareTryEchViaPanelDoh = true;
  bool _cloudflareUseCachedEchFallback = true;
  bool _panelUseProxyForUpdate = false;
  bool _panelForceCleanIpsForUpdate = false;
  bool _panelEnableProxyDiagnostics = false;
  bool _useServerBackend = false;
  UpdateMode _updateMode = UpdateMode.cloudflareApi;

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
    _serverBaseUrlController.dispose();
    _serverTokenController.dispose();
    _serverUsernameController.dispose();
    _serverPasswordController.dispose();
    _panelDohUrlOverrideController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _log.logInfo('SettingsScreen: Loading settings on startup');
    setState(() => _isLoading = true);

    final mode = await _storage.getUpdateMode();
    final credentials = await _storage.getCredentials();
    final panelCredentials = await _storage.getPanelCredentials();
    final autoApplyAfterScan = await _storage.getAutoApplyAfterScan();
    final cloudflareTryEchViaProxy = await _storage
        .getCloudflareTryEchViaProxy();
    final cloudflareTryEchViaDirectResolvers = await _storage
        .getCloudflareTryEchViaDirectResolvers();
    final cloudflareTryEchViaPanelDoh = await _storage
        .getCloudflareTryEchViaPanelDoh();
    final cloudflareUseCachedEchFallback = await _storage
        .getCloudflareUseCachedEchFallback();
    final panelDohUrlOverride = await _storage
        .getCloudflarePanelDohUrlOverride();
    final panelUseProxyForUpdate = await _storage.getPanelUseProxyForUpdate();
    final panelForceCleanIpsForUpdate = await _storage
        .getPanelForceCleanIpsForUpdate();
    final panelEnableProxyDiagnostics = await _storage
        .getPanelEnableProxyDiagnostics();
    final useServerBackend = await _storage.getUseServerBackend();
    final serverBaseUrl = await _storage.getServerBackendBaseUrl();
    final serverToken = await _storage.getServerBackendToken();
    final serverUsername = await _storage.getServerBackendWebUsername();
    final serverJwt = await _storage.getServerBackendJwt();

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
    if (serverBaseUrl != null) {
      _serverBaseUrlController.text = serverBaseUrl;
    }
    if (serverToken != null) {
      _serverTokenController.text = serverToken;
    }
    if (serverUsername != null) {
      _serverUsernameController.text = serverUsername;
    }
    final effectiveUseServerBackend = kIsWeb ? true : useServerBackend;
    final hasWebSession = (serverJwt ?? '').trim().isNotEmpty;
    setState(() {
      _hasCredentials = effectiveUseServerBackend
          ? (kIsWeb
                ? _serverBaseUrlController.text.trim().isNotEmpty &&
                      _serverUsernameController.text.trim().isNotEmpty &&
                      hasWebSession
                : _serverBaseUrlController.text.trim().isNotEmpty ||
                      _serverTokenController.text.trim().isNotEmpty)
          : _hasCredentialsForMode(_updateMode);
      _autoApplyAfterScan = autoApplyAfterScan;
      _cloudflareTryEchViaProxy = cloudflareTryEchViaProxy;
      _cloudflareTryEchViaDirectResolvers = cloudflareTryEchViaDirectResolvers;
      _cloudflareTryEchViaPanelDoh = cloudflareTryEchViaPanelDoh;
      _cloudflareUseCachedEchFallback = cloudflareUseCachedEchFallback;
      _panelDohUrlOverrideController.text = panelDohUrlOverride ?? '';
      _panelUseProxyForUpdate = panelUseProxyForUpdate;
      _panelForceCleanIpsForUpdate = panelForceCleanIpsForUpdate;
      _panelEnableProxyDiagnostics = panelEnableProxyDiagnostics;
      _useServerBackend = effectiveUseServerBackend;
      _isLoading = false;
    });
    if (kIsWeb && !useServerBackend) {
      await _storage.saveUseServerBackend(true);
    }

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
      await _storage.saveUseServerBackend(kIsWeb ? true : _useServerBackend);

      if (_useServerBackend) {
        await _storage.saveServerBackendBaseUrl(
          _serverBaseUrlController.text.trim(),
        );
        if (kIsWeb) {
          await _storage.saveServerBackendWebUsername(
            _serverUsernameController.text.trim(),
          );
        } else {
          await _storage.saveServerBackendToken(
            _serverTokenController.text.trim(),
          );
        }
        final hasWebSession =
            ((await _storage.getServerBackendJwt())?.trim() ?? '').isNotEmpty;

        setState(() {
          _isLoading = false;
          _hasCredentials = kIsWeb
              ? _serverBaseUrlController.text.trim().isNotEmpty &&
                    _serverUsernameController.text.trim().isNotEmpty &&
                    hasWebSession
              : _serverBaseUrlController.text.trim().isNotEmpty ||
                    _serverTokenController.text.trim().isNotEmpty;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb && !hasWebSession
                  ? 'Settings saved. Click Sign In to create a web session.'
                  : 'Server backend settings saved successfully',
            ),
            backgroundColor: (kIsWeb && !hasWebSession)
                ? Colors.orange
                : Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

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
      }

      await _storage.saveUpdateMode(_updateMode);
      await _storage.saveAutoApplyAfterScan(_autoApplyAfterScan);
      await _storage.saveCloudflareTryEchViaProxy(_cloudflareTryEchViaProxy);
      await _storage.saveCloudflareTryEchViaDirectResolvers(
        _cloudflareTryEchViaDirectResolvers,
      );
      await _storage.saveCloudflareTryEchViaPanelDoh(
        _cloudflareTryEchViaPanelDoh,
      );
      await _storage.saveCloudflareUseCachedEchFallback(
        _cloudflareUseCachedEchFallback,
      );
      await _storage.saveCloudflarePanelDohUrlOverride(
        _panelDohUrlOverrideController.text,
      );
      await _storage.savePanelUseProxyForUpdate(_panelUseProxyForUpdate);
      await _storage.savePanelForceCleanIpsForUpdate(
        _panelForceCleanIpsForUpdate,
      );
      await _storage.savePanelEnableProxyDiagnostics(
        _panelEnableProxyDiagnostics,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasCredentials = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _updateMode == UpdateMode.cloudflareApi
                ? 'Cloudflare settings saved successfully'
                : 'Panel API settings saved successfully',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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

    if (_useServerBackend) {
      final baseUrl = _serverBaseUrlController.text.trim();
      bool isValid = false;
      Object? validationError;
      try {
        if (kIsWeb) {
          final jwt = (await _storage.getServerBackendJwt())?.trim();
          await _serverApi.getStatus(baseUrl: baseUrl, authToken: jwt);
        } else {
          await _serverApi.getStatus(baseUrl: baseUrl);
        }
        isValid = true;
      } catch (e, stackTrace) {
        validationError = e;
        _log.logError('Failed to validate server backend', e, stackTrace);
      }
      setState(() => _isValidating = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isValid
                ? kIsWeb
                      ? 'Server connection and web session are valid.'
                      : 'Server is reachable. Token was not verified. Trigger/rollback actions will fail if token is incorrect.'
                : (kIsWeb && validationError != null)
                ? _friendlyWebServerError(
                    baseUrl: baseUrl,
                    error: validationError,
                  )
                : 'Server backend validation failed: $validationError',
          ),
          backgroundColor: isValid ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
          _useServerBackend
              ? 'Clear saved server backend credentials?'
              : _updateMode == UpdateMode.cloudflareApi
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

    if (_useServerBackend) {
      await _storage.saveServerBackendBaseUrl('');
      await _storage.clearServerBackendToken();
      await _storage.clearServerBackendJwt();
      await _storage.saveServerBackendWebUsername('');
      _serverBaseUrlController.clear();
      _serverTokenController.clear();
      _serverUsernameController.clear();
      _serverPasswordController.clear();
      setState(() => _hasCredentials = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server backend credentials cleared'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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
        labelText: 'Local Apply Method',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.sync_alt),
      ),
      items: UpdateMode.values
          .map(
            (mode) => DropdownMenuItem<UpdateMode>(
              value: mode,
              child: Text(
                mode == UpdateMode.cloudflareApi
                    ? '${mode.displayName} (Recommended)'
                    : mode.displayName,
              ),
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
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'BPB Panel v4.1.3+: if ECH Server Name is set in panel settings, ECH generation is handled by client cores (Xray/sing-box). Use a domain that returns an HTTPS record with ech=. If no reliable domain is found, leave ECH Server Name empty and BPB Automation will continue ECH fallback handling.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue.shade900,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Try ECH refresh via direct DoH resolvers'),
          subtitle: const Text(
            'Uses dns.google and cloudflare-dns.com first. Disable this if your network consistently blocks public DoH.',
          ),
          value: _cloudflareTryEchViaDirectResolvers,
          onChanged: (value) {
            setState(() => _cloudflareTryEchViaDirectResolvers = value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Try ECH refresh via panel DoH'),
          subtitle: const Text(
            'Uses your panel /dns-query route for ECH lookup. Useful when public DoH is filtered.',
          ),
          value: _cloudflareTryEchViaPanelDoh,
          onChanged: (value) {
            setState(() => _cloudflareTryEchViaPanelDoh = value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Try ECH refresh via proxy (Experimental)'),
          subtitle: const Text(
            'Experimental and not always reliable. Disabled by default. If enabled, app may try Xray + clean IPs when direct ECH lookup fails. This can increase apply time.',
          ),
          value: _cloudflareTryEchViaProxy,
          onChanged: (value) {
            setState(() => _cloudflareTryEchViaProxy = value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use last successful ECH when refresh fails'),
          subtitle: const Text(
            'If enabled, app can reuse previously fetched ECH config when network blocks live DoH lookup.',
          ),
          value: _cloudflareUseCachedEchFallback,
          onChanged: (value) {
            setState(() => _cloudflareUseCachedEchFallback = value);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _panelDohUrlOverrideController,
          decoration: const InputDecoration(
            labelText: 'Panel DoH URL override (optional)',
            hintText: 'https://your-domain/dns-query/<subPath>',
            border: OutlineInputBorder(),
            helperText:
                'If set, ECH lookup uses this URL first. Leave empty to auto-derive from saved subscription URL.',
          ),
          keyboardType: TextInputType.url,
          validator: (value) {
            if (_updateMode != UpdateMode.cloudflareApi) return null;
            final raw = value?.trim() ?? '';
            if (raw.isEmpty) return null;
            final uri = Uri.tryParse(raw);
            if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
              return 'Enter a valid absolute URL';
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
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use proxy for panel update (Experimental)'),
          subtitle: const Text(
            'Experimental and not always reliable. If enabled, panel apply tries through Xray and clean IP candidates.',
          ),
          value: _panelUseProxyForUpdate,
          onChanged: (value) {
            setState(() {
              _panelUseProxyForUpdate = value;
              if (!value) {
                _panelEnableProxyDiagnostics = false;
              }
            });
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable panel proxy diagnostics'),
          subtitle: const Text(
            'Runs extra proxy debug checks (GET /, GET /panel, POST /login/authenticate). Default off.',
          ),
          value: _panelEnableProxyDiagnostics,
          onChanged: _panelUseProxyForUpdate
              ? (value) {
                  setState(() => _panelEnableProxyDiagnostics = value);
                }
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Force clean IPs for panel when proxy is off'),
          subtitle: const Text(
            'When proxy mode is disabled, connect panel domain through clean IP candidates directly and rotate until one succeeds.',
          ),
          value: _panelForceCleanIpsForUpdate,
          onChanged: _panelUseProxyForUpdate
              ? null
              : (value) {
                  setState(() => _panelForceCleanIpsForUpdate = value);
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

  Future<void> _signInServerBackendWeb() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final baseUrl = _serverBaseUrlController.text.trim();
    final username = _serverUsernameController.text.trim();
    final password = _serverPasswordController.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your web login password first.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isServerSigningIn = true);
    try {
      final token = await _serverApi.login(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      // Verify session can actually access protected API before persisting state.
      await _serverApi.getStatus(baseUrl: baseUrl, authToken: token);
      await _storage.saveServerBackendBaseUrl(baseUrl);
      await _storage.saveServerBackendWebUsername(username);
      await _storage.saveServerBackendJwt(token);
      _serverPasswordController.clear();
      if (!mounted) return;
      setState(() => _hasCredentials = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server web login successful'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stackTrace) {
      _log.logError('Server web login failed', e, stackTrace);
      if (!mounted) return;
      final message = _friendlyWebServerError(baseUrl: baseUrl, error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isServerSigningIn = false);
      }
    }
  }

  String _friendlyWebServerError({
    required String baseUrl,
    required Object error,
  }) {
    if (!kIsWeb) return 'Login failed: $error';
    final text = error.toString();
    if (text.contains('XMLHttpRequest error')) {
      return 'Cannot reach $baseUrl from browser (likely CORS or backend not running). '
          'Start backend and set --cors-allowed-origins to this web origin.';
    }
    return 'Login failed: $error';
  }

  Widget _buildServerBackendCard() {
    final executionMode = _useServerBackend ? 'server' : 'local';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Execution Mode',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (kIsWeb)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock),
            title: Text('Server Backend (Web required, WIP)'),
            subtitle: Text(
              'WIP / Experimental: Web builds run in server backend mode and require sign-in.',
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: executionMode,
            decoration: const InputDecoration(
              labelText: 'Execution Mode',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.developer_board),
            ),
            items: const [
              DropdownMenuItem(
                value: 'local',
                child: Text('Local Device Scanner'),
              ),
              DropdownMenuItem(
                value: 'server',
                child: Text('Server Backend (WIP)'),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              final useServer = value == 'server';
              if (!mounted) return;
              setState(() {
                _useServerBackend = useServer;
                _hasCredentials = useServer
                    ? _serverBaseUrlController.text.trim().isNotEmpty ||
                          _serverTokenController.text.trim().isNotEmpty
                    : _hasCredentialsForMode(_updateMode);
              });
            },
          ),
        const SizedBox(height: 8),
        Text(
          _useServerBackend
              ? 'Server mode (WIP) is active. Home/Results/Logs actions use server endpoints.'
              : 'Local mode is active. Scans run on this device.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildServerBackendInlineForm() {
    final showWeb = kIsWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Server Backend Settings',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const ExperimentalServerBanner(
          message:
              'WIP / Experimental: server and web backend control actions are not fully stable yet.',
        ),
        const SizedBox(height: 8),
        Text(
          'When enabled, Home/Results/Logs actions use server endpoints and server run history.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _serverBaseUrlController,
          decoration: const InputDecoration(
            labelText: 'Backend Base URL',
            hintText: 'https://scan.example.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.dns),
          ),
          keyboardType: TextInputType.url,
          validator: (value) {
            if (!_useServerBackend) return null;
            final raw = (value ?? '').trim();
            if (raw.isEmpty) {
              return 'Backend base URL is required when server mode is enabled';
            }
            final uri = Uri.tryParse(raw);
            if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
              return 'Enter a valid absolute URL';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        if (showWeb) ...[
          TextFormField(
            controller: _serverUsernameController,
            decoration: const InputDecoration(
              labelText: 'Web Login Username',
              hintText: 'Username configured on backend',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (!_useServerBackend || !kIsWeb) return null;
              if ((value ?? '').trim().isEmpty) {
                return 'Username is required for web login';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _serverPasswordController,
            decoration: InputDecoration(
              labelText: 'Web Login Password',
              hintText: 'Password configured on backend',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureServerPassword
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(
                    () => _obscureServerPassword = !_obscureServerPassword,
                  );
                },
              ),
            ),
            obscureText: _obscureServerPassword,
          ),
          const SizedBox(height: 8),
          Text(
            'Web mode stores only a JWT session token locally. Your password is not persisted.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
          ),
        ] else
          TextFormField(
            controller: _serverTokenController,
            decoration: InputDecoration(
              labelText: 'Internal Trigger Token',
              hintText: 'Required for trigger/rollback actions',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureServerToken ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscureServerToken = !_obscureServerToken);
                },
              ),
            ),
            obscureText: _obscureServerToken,
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
          const LogsActionButton(currentRoute: '/settings'),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
            onPressed: _isLoading ? null : _saveCurrentCredentials,
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
                      _buildServerBackendCard(),
                      const SizedBox(height: 24),
                      if (_useServerBackend) ...[
                        _buildServerBackendInlineForm(),
                        const SizedBox(height: 24),
                      ] else ...[
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
                      ],
                      const SizedBox(height: 24),
                      if (_useServerBackend && kIsWeb)
                        ElevatedButton.icon(
                          onPressed: _isServerSigningIn
                              ? null
                              : _signInServerBackendWeb,
                          icon: _isServerSigningIn
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            _isServerSigningIn
                                ? 'Signing in...'
                                : 'Sign In and Verify',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
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
                            _useServerBackend
                                ? 'Clear Server Backend Credentials'
                                : _updateMode == UpdateMode.cloudflareApi
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
