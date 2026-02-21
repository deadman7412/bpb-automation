import 'package:flutter/material.dart';

import '../services/theme_service.dart';

class ThemeModeActionButton extends StatelessWidget {
  const ThemeModeActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.themeModeListenable,
      builder: (context, mode, _) {
        final icon = switch (mode) {
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
          ThemeMode.system => Icons.brightness_auto,
        };

        return PopupMenuButton<ThemeMode>(
          tooltip: 'Theme',
          icon: Icon(icon),
          onSelected: (selected) {
            ThemeService.instance.setThemeMode(selected);
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem<ThemeMode>(
              value: ThemeMode.system,
              checked: mode == ThemeMode.system,
              child: const Text('System'),
            ),
            CheckedPopupMenuItem<ThemeMode>(
              value: ThemeMode.light,
              checked: mode == ThemeMode.light,
              child: const Text('Light'),
            ),
            CheckedPopupMenuItem<ThemeMode>(
              value: ThemeMode.dark,
              checked: mode == ThemeMode.dark,
              child: const Text('Dark'),
            ),
          ],
        );
      },
    );
  }
}
