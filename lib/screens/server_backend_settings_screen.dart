import 'package:flutter/material.dart';

import '../services/log_service.dart';
import '../services/server_backend_service.dart';
import '../services/storage_service.dart';
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
  final StorageService _storage = StorageService.instance;
  final ServerBackendService _serverApi = ServerBackendService.instance;
  final LogService _log = LogService.instance;

  bool _loading = false;
  bool _validating = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverBaseUrlController.dispose();
    _serverTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final baseUrl = await _storage.getServerBackendBaseUrl();
    final token = await _storage.getServerBackendToken();
    _serverBaseUrlController.text = baseUrl ?? '';
    _serverTokenController.text = token ?? '';
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
      await _storage.saveServerBackendToken(_serverTokenController.text.trim());
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
      await _serverApi.getStatus(baseUrl: baseUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Server is reachable. Token was not verified. Trigger/rollback actions will fail if token is incorrect.',
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
    _serverBaseUrlController.clear();
    _serverTokenController.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Server backend credentials cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Backend'),
        actions: const [LogsActionButton()],
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
                                'When enabled, Home/Results/Logs actions use the server backend, not this local device scanner. Use this when a VPS or another device performs scheduled scans.',
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
                      TextFormField(
                        controller: _serverTokenController,
                        decoration: InputDecoration(
                          labelText: 'Internal Trigger Token',
                          hintText: 'Required for run/rollback trigger actions',
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
