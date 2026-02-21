import 'package:flutter/material.dart';

/// Reusable AppBar action group in required order:
/// Log
class LogsActionButton extends StatelessWidget {
  const LogsActionButton({super.key, this.currentRoute});

  final String? currentRoute;

  bool _isCurrent(String routeName) => currentRoute == routeName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.list_alt),
          tooltip: 'Logs',
          onPressed: _isCurrent('/logs')
              ? null
              : () => Navigator.pushNamed(context, '/logs'),
        ),
      ],
    );
  }
}
