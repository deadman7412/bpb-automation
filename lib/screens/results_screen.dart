import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/clean_ip.dart';
import '../services/storage_service.dart';
import '../services/cloudflare_api_service.dart';
import '../services/log_service.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final StorageService _storage = StorageService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;
  final LogService _log = LogService.instance;

  List<CleanIP> _results = [];
  bool _sortByLatency = false; // Default to sort by speed
  int _numIPsToUse = 5;
  bool _isLoaded = false;
  bool _isUpdating = false;
  DateTime? _scanTime;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isLoaded) {
      _loadResults();
      _isLoaded = true;
    }
  }

  Future<void> _loadResults() async {
    // Try to get results from route arguments first
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is List<CleanIP>) {
      setState(() {
        _results = args;
      });
      _log.logInfo('Loaded ${_results.length} results from navigation arguments');
    } else {
      // If no arguments, try to load last saved results
      _log.logInfo('No route arguments, loading last saved results');
      final savedResults = await _storage.getLastScanResults();
      if (savedResults != null && savedResults.isNotEmpty) {
        setState(() {
          _results = savedResults.map((json) => CleanIP.fromJson(json)).toList();
        });
        _log.logOk('Loaded ${_results.length} results from storage');
      } else {
        _log.logInfo('No saved results found');
      }
    }

    // Load scan timestamp
    final scanTime = await _storage.getLastScanTime();
    setState(() {
      _scanTime = scanTime;
    });

    // Load num IPs to use from storage
    final numIps = await _storage.getNumIpsToUse();
    setState(() {
      _numIPsToUse = numIps.clamp(1, _results.isNotEmpty ? _results.length : 20);
    });

    _sortResults();
  }

  void _sortResults() {
    setState(() {
      if (_sortByLatency) {
        _results.sort((a, b) => a.avgLatency.compareTo(b.avgLatency));
      } else {
        _results.sort((a, b) => b.downloadSpeed.compareTo(a.downloadSpeed));
      }
    });
  }

  Future<void> _updateBPB() async {
    // Step 1: Get credentials
    final credentials = await _storage.getCredentials();
    if (credentials == null || !credentials.isValid()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure your Cloudflare credentials first'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pushNamed(context, '/settings');
      return;
    }

    // Step 2: Select top N IPs
    final selectedIPs = _results.take(_numIPsToUse).map((ip) => ip.ip).toList();
    _log.logInfo('Updating BPB Panel with ${selectedIPs.length} clean IPs');

    setState(() => _isUpdating = true);

    try {
      // Step 3: Show confirmation dialog
      if (!mounted) {
        setState(() => _isUpdating = false);
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update BPB Panel'),
          content: Text(
            'This will update your BPB Panel configuration with ${selectedIPs.length} clean IPs.\n\n'
            'Selected IPs:\n${selectedIPs.take(5).join('\n')}${selectedIPs.length > 5 ? '\n...' : ''}\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isUpdating = false);
        return;
      }

      if (!mounted) {
        setState(() => _isUpdating = false);
        return;
      }

      // Step 4: Update via Cloudflare API
      _log.logInfo('Calling Cloudflare API to update cleanIPs...');
      final success = await _api.updateCleanIPs(credentials, selectedIPs);

      setState(() => _isUpdating = false);

      if (!mounted) return;

      if (success) {
        _log.logOk('BPB Panel updated successfully with ${selectedIPs.length} clean IPs');

        // Save num IPs to use for next time
        await _storage.saveNumIpsToUse(_numIPsToUse);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('BPB Panel updated successfully with ${selectedIPs.length} clean IPs'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        _log.logError('Failed to update BPB Panel');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update BPB Panel. Check logs for details.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      _log.logError('Error updating BPB Panel', e, stackTrace);

      setState(() => _isUpdating = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _updateBPB,
          ),
        ),
      );
    }
  }

  Future<void> _exportResults() async {
    final selectedIPs = _results.take(_numIPsToUse).map((ip) => ip.ip).toList();
    final text = selectedIPs.join('\n');

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedIPs.length} IPs copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acceptableResults = _results.where((ip) => ip.isAcceptable()).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan Results'),
            if (_scanTime != null)
              Text(
                'Last scan: ${_formatTimeAgo(_scanTime!)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Home',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Summary Card
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(
                          context,
                          'Total IPs',
                          _results.length.toString(),
                          Icons.list,
                        ),
                        _buildSummaryItem(
                          context,
                          'Acceptable',
                          acceptableResults.length.toString(),
                          Icons.check_circle,
                        ),
                        _buildSummaryItem(
                          context,
                          'Selected',
                          _numIPsToUse.toString(),
                          Icons.star,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Number of IPs to use: $_numIPsToUse',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: acceptableResults.isEmpty
                              ? const SizedBox.shrink()
                              : Slider(
                                  value: _numIPsToUse.toDouble().clamp(1.0, acceptableResults.length.toDouble()),
                                  min: 1,
                                  max: acceptableResults.length.toDouble(),
                                  divisions: acceptableResults.length - 1,
                                  label: _numIPsToUse.toString(),
                                  onChanged: (value) {
                                    setState(() => _numIPsToUse = value.toInt());
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Sort Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Sort by:'),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text('Latency'),
                    selected: _sortByLatency,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _sortByLatency = true);
                        _sortResults();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Speed'),
                    selected: !_sortByLatency,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _sortByLatency = false);
                        _sortResults();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Results List
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'No scan results yet',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Run a scan to see results here',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final ip = _results[index];
                        final isSelected = index < _numIPsToUse;
                        final isAcceptable = ip.isAcceptable();

                        return Card(
                          color: isSelected
                              ? Colors.blue.shade100
                              : isAcceptable
                                  ? null
                                  : Colors.grey.shade100,
                          elevation: isSelected ? 2 : 1,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Colors.blue.shade700
                                  : isAcceptable
                                      ? Colors.green
                                      : Colors.grey,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              ip.ip,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.black87 : null,
                              ),
                            ),
                            subtitle: Text(
                              'Latency: ${ip.avgLatency.toStringAsFixed(1)}ms  '
                              'Loss: ${ip.lossRate.toStringAsFixed(1)}%  '
                              'Speed: ${ip.downloadSpeed.toStringAsFixed(1)}MB/s',
                              style: TextStyle(
                                color: isSelected ? Colors.black87 : null,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                                : isAcceptable
                                    ? null
                                    : const Icon(Icons.warning, color: Colors.orange),
                          ),
                        );
                      },
                    ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _results.isEmpty ? null : _exportResults,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy IPs'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_results.isEmpty || _isUpdating) ? null : _updateBPB,
                      icon: _isUpdating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(_isUpdating ? 'Updating...' : 'Update BPB'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      // Show date for older scans
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }
}
