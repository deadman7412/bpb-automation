import 'package:flutter/material.dart';

/// Reusable AppBar action to open the Logs screen.
class LogsActionButton extends StatelessWidget {
  const LogsActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.list_alt),
      tooltip: 'Logs',
      onPressed: () => Navigator.pushNamed(context, '/logs'),
    );
  }
}
