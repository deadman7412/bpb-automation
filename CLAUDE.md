# BPB Automation

Cross-platform automation tool for BPB Panel - automatically scan and update clean Cloudflare IPs.

## Project Overview

This Flutter application wraps the Cloudflare Clean IP Scanner binary and provides a user-friendly interface to:
- Scan for clean Cloudflare IPs from your actual network (mobile ISP, home internet, etc.)
- Automatically update BPB Panel settings via Panel API (default) or Cloudflare API (fallback)
- Work offline-first (no hosting required, runs locally on device)
- Support multiple platforms: Android, macOS, Linux, Windows, Web, iOS

## Key Requirements

### Platform Priority
1. **Android** - Primary target, APK distribution
2. **macOS** - Desktop support
3. **Linux** - Desktop support
4. **Windows** - Desktop support
5. **Web** - VPS deployment with cronjob capability
6. **iOS** - Future support

### Core Features
- Bundle platform-specific scanner binaries
- Clean, user-friendly UI (no terminal required)
- Secure credential storage (encrypted locally)
- Default scanner settings with advanced configuration menu
- Real-time scan progress and results display
- Dual update integration: Panel API + Cloudflare Workers KV API

### Critical Rules
- **STRICTLY FORBIDDEN**: Use of emojis anywhere in code, UI, or documentation
- **Logging System**: Use tags `[OK]` `[INFO]` `[WARN]` `[ERROR]` for all logging
- **Security**: NO references to development machine, environment, or developer information in the app
- **STRICTLY FORBIDDEN - No Personal Info**: NEVER write real usernames, real machine names, real local paths, or any developer-identifying information anywhere in code, docs, comments, or examples. This includes but is not limited to: real usernames in paths (e.g. `/Users/<username>`), machine names (e.g. specific laptop/desktop names), developer names, or any environment-specific values. Always use generic placeholders: `/path/to/your/projects`, `<your-machine>`, `some-user`, etc.

## Technical Stack

- **Framework**: Flutter (Dart)
- **Scanner**: Cloudflare-Clean-IP-Scanner binaries (Go)
- **API**: BPB Panel API + Cloudflare Workers KV REST API
- **Storage**: flutter_secure_storage for credentials

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed technical architecture.

## Documentation Structure

- [docs/architecture.md](docs/architecture.md) - Technical architecture and design
- [docs/panel-setup.md](docs/panel-setup.md) - How to configure Panel API credentials
- [docs/panel-api-reference.md](docs/panel-api-reference.md) - Full BPB panel route and API reference
- [docs/cloudflare-setup.md](docs/cloudflare-setup.md) - How to obtain Cloudflare credentials
- [docs/scanner-configuration.md](docs/scanner-configuration.md) - Scanner parameters and configuration
- [docs/development.md](docs/development.md) - Development setup and guidelines
- [docs/deployment.md](docs/deployment.md) - Building and distributing for different platforms
- [docs/user-guide.md](docs/user-guide.md) - End-user documentation
- [docs/project-timeline.md](docs/project-timeline.md) - Project phases, tasks, and progress tracking

## Project Structure

```
bpb-automation/
├── CLAUDE.md                 # This file
├── README.md                 # User-facing readme
├── docs/                     # Documentation
├── lib/                      # Flutter app source
│   ├── main.dart
│   ├── models/              # Data models
│   ├── services/            # Business logic
│   │   ├── dart_scanner_service.dart
│   │   ├── cloudflare_api_service.dart
│   │   ├── panel_api_service.dart
│   │   └── storage_service.dart
│   ├── screens/             # UI screens
│   └── widgets/             # Reusable widgets
├── assets/                  # Assets
│   └── binaries/            # Scanner binaries
│       ├── android-arm64/
│       ├── darwin-amd64/
│       ├── darwin-arm64/
│       ├── linux-amd64/
│       ├── windows-amd64/
│       └── README.md
├── test/                    # Tests
└── pubspec.yaml            # Flutter dependencies
```

## Development Environment

- Flutter SDK (latest stable)
- Android Studio (for Android builds)
- Xcode (for macOS/iOS builds)
- Android emulator available for testing

## Getting Started

See [docs/development.md](docs/development.md) for setup instructions.

## User Guide

See [docs/user-guide.md](docs/user-guide.md) for end-user documentation including both update methods.

## Security Considerations

- API tokens stored using flutter_secure_storage (encrypted)
- No hardcoded credentials
- No telemetry or analytics
- Runs completely local, no data sent to third parties
- All network requests only to BPB panel endpoints, Cloudflare API endpoints, and required scan targets

## Project Development Workflow

This project follows a phased development approach with strict gate controls:

1. **Phase-Based Development**: Work proceeds through 10 defined phases (see [docs/project-timeline.md](docs/project-timeline.md))
2. **Task Completion**: Each task must be completed fully before marking as done
3. **Completion Reports**: Every completed task requires a filled completion report with:
   - Completion date
   - Summary of work done
   - Issues encountered and resolutions
   - Relevant metrics or test results
4. **Phase Gates**: Cannot advance to next phase until:
   - All tasks in current phase are completed
   - All task reports are filled
   - Phase gate review checklist is completed
   - Gate review approval is documented
5. **No Skipping**: Tasks cannot be skipped unless explicitly documented with reasoning

### Current Phase Status

Check [docs/project-timeline.md](docs/project-timeline.md) for current phase and task status.

### Development Rules When Working on Tasks

- **Before starting a task**: Update task status to "IN PROGRESS" in project-timeline.md
- **While working**: Follow acceptance criteria exactly
- **After completing**: Fill out completion report immediately
- **Testing**: All code changes must include appropriate tests
- **Documentation**: Update relevant docs as you implement features

## License

To be determined
