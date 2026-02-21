import 'package:flutter/material.dart';

import 'storage_service.dart';

class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _keyThemeMode = 'theme_mode';
  final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  ValueNotifier<ThemeMode> get themeModeListenable => _themeModeNotifier;
  ThemeMode get themeMode => _themeModeNotifier.value;

  Future<void> initialize() async {
    final value = await StorageService.instance.getString(_keyThemeMode);
    _themeModeNotifier.value = _parse(value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeModeNotifier.value = mode;
    await StorageService.instance.saveString(_keyThemeMode, _toStorage(mode));
  }

  ThemeMode _parse(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _toStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
