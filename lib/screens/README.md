# Screens Directory

This directory contains top-level UI screens (pages) of the application.

## Purpose

Screens are full-page views that users navigate between.

## Screens

### HomeScreen
Main screen with scan button and status display.

### SettingsScreen
Credential management and basic configuration.

### ResultsScreen
Display scan results and clean IP list.

### LogsScreen
Application logs viewer with filtering.

### AdvancedConfigScreen
Advanced scanner parameter configuration.

## Guidelines

- Each screen should be a StatefulWidget or StatelessWidget
- Keep business logic in services, not screens
- Use widgets directory for reusable components
- Follow Material Design guidelines
- Ensure responsive layouts for different screen sizes
- Handle loading and error states appropriately
- NO EMOJIS in any UI text
