import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/log_service.dart';
import '../services/server_backend_service.dart';
import '../services/storage_service.dart';
import '../widgets/experimental_server_banner.dart';
import '../widgets/logs_action_button.dart';

class ServerBackendSettingsScreen extends StatefulWidget {
  const ServerBackendSettingsScreen({super.key});

  @override
  State<ServerBackendSettingsScreen> createState() =>
      _ServerBackendSettingsScreenState();
}

class _ServerBackendSettingsScreenState
    extends State<ServerBackendSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverBaseUrlController = TextEditingController();
  final _serverTokenController = TextEditingController();
  final _serverUsernameController = TextEditingController();
  final _serverPasswordController = TextEditingController();
  final StorageService _storage = StorageService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;
  final LogService _log = LogService.instance;

  bool _loading = false;
  bool _validating = false;
  bool _signingIn = false;
  bool _obscureToken = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverBaseUrlController.dispose();
    _serverTokenController.dispose();
    _serverUsernameController.dispose();
    _serverPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final baseUrl = await _storage.getServerBackendBaseUrl();
    final token = await _storage.getServerBackendToken();
    final username = await _storage.getServerBackendWebUsername();
    _serverBaseUrlController.text = baseUrl ?? '';
    _serverTokenController.text = token ?? '';
    _serverUsernameController.text = username ?? '';
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _loading = true);
    try {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server backend settings saved'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      _log.logError('Failed to save server backend settings', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _validate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final baseUrl = _serverBaseUrlController.text.trim();
    setState(() => _validating = true);
    try {
      final authToken = kIsWeb
          ? (await _storage.getServerBackendJwt())?.trim()
          : null;
      await _serverApi.getStatus(baseUrl: baseUrl, authToken: authToken);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Server connection and web session are valid.'
                : 'Server is reachable. Token was not verified. Trigger/rollback actions will fail if token is incorrect.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      _log.logError('Server backend validation failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Validation failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _validating = false);
      }
    }
  }

  Future<void> _clear() async {
    await _storage.saveServerBackendBaseUrl('');
    await _storage.clearServerBackendToken();
    await _storage.clearServerBackendJwt();
    await _storage.saveServerBackendWebUsername('');
    _serverBaseUrlController.clear();
    _serverTokenController.clear();
    _serverUsernameController.clear();
    _serverPasswordController.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Server backend credentials cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signInWeb() async {
    if (!_formKey.currentState!.validate()) return;
    if (_serverPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter web login password first.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _signingIn = true);
    try {
      final token = await _serverApi.login(
        baseUrl: _serverBaseUrlController.text.trim(),
        username: _serverUsernameController.text.trim(),
        password: _serverPasswordController.text,
      );
      await _serverApi.getStatus(
        baseUrl: _serverBaseUrlController.text.trim(),
        authToken: token,
      );
      await _storage.saveServerBackendBaseUrl(
        _serverBaseUrlController.text.trim(),
      );
      await _storage.saveServerBackendWebUsername(
        _serverUsernameController.text.trim(),
      );
      await _storage.saveServerBackendJwt(token);
      _serverPasswordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server web login successful'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      _log.logError('Server web login failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Backend (WIP)'),
        actions: const [
          LogsActionButton(currentRoute: '/server-backend-settings'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ExperimentalServerBanner(),
                      const SizedBox(height: 12),
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Server mode behavior',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'WIP / Experimental: server mode can be partially functional. '
                                'When enabled, Home/Results/Logs actions use the server backend, not this local device scanner.',
                              ),
                            ],
                          ),
                        ),
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
                          final raw = (value ?? '').trim();
                          if (raw.isEmpty) {
                            return 'Backend base URL is required';
                          }
                          final uri = Uri.tryParse(raw);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.isEmpty) {
                            return 'Enter a valid absolute URL';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      if (kIsWeb) ...[
                        TextFormField(
                          controller: _serverUsernameController,
                          decoration: const InputDecoration(
                            labelText: 'Web Login Username',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _serverPasswordController,
                          decoration: InputDecoration(
                            labelText: 'Web Login Password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                        ),
                      ] else
                        TextFormField(
                          controller: _serverTokenController,
                          decoration: InputDecoration(
                            labelText: 'Internal Trigger Token',
                            hintText:
                                'Required for run/rollback trigger actions',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.key),
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
                          ),
                          obscureText: _obscureToken,
                        ),
                      const SizedBox(height: 16),
                      if (kIsWeb)
                        ElevatedButton.icon(
                          onPressed: _signingIn ? null : _signInWeb,
                          icon: _signingIn
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
                            _signingIn ? 'Signing in...' : 'Sign In and Verify',
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
                                onPressed: _validating ? null : _validate,
                                icon: _validating
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
                                  _validating ? 'Validating...' : 'Validate',
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
                                onPressed: _save,
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
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear Server Backend Credentials'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
