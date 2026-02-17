# Releasing Guide

This guide explains how to create a new release of BPB Automation.

## Release Process Overview

BPB Automation uses GitHub Actions for automated builds and releases. When you push a version tag, the CI/CD pipeline automatically:
1. Builds APKs for Android
2. Builds DMG for macOS
3. Builds tar.gz for Linux
4. Builds ZIP for Windows
5. Creates a GitHub Release with all artifacts attached

## Version Numbering

Format: `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR**: Breaking changes, major features
- **MINOR**: New features, non-breaking changes
- **PATCH**: Bug fixes, minor improvements
- **BUILD**: Build number (increment with each release)

Example: `1.2.0+6`

## Pre-Release Checklist

Before creating a release, ensure:

- [ ] All tests passing: `flutter test`
- [ ] No analyzer warnings: `flutter analyze`
- [ ] Code formatted: `dart format .`
- [ ] All changes committed
- [ ] CHANGELOG.md updated (if exists)
- [ ] Icons generated: `flutter pub run flutter_launcher_icons`
- [ ] Local builds work on target platforms

## Step-by-Step Release Process

### 1. Update Version Number

Edit `pubspec.yaml` and update the version:

```yaml
version: 1.2.0+6
```

Version format:
- First three numbers: `MAJOR.MINOR.PATCH` (shown to users)
- After `+`: Build number (Android versionCode, iOS CFBundleVersion)

### 2. Commit Version Bump

```bash
git add pubspec.yaml
git commit -m "Bump version to 1.2.0+6"
```

### 3. Create and Push Tag

```bash
# Create annotated tag
git tag -a v1.2.0 -m "Release v1.2.0: [Brief description]"

# Push commits and tag
git push origin main
git push origin v1.2.0
```

### 4. GitHub Actions Builds Everything

Once you push the tag, GitHub Actions automatically:

1. **Runs CI checks**:
   - Flutter analyze
   - Flutter test
   
2. **Builds for all platforms**:
   - Android: Debug + Release APKs
   - macOS: Release DMG
   - Linux: Release tar.gz
   - Windows: Release ZIP

3. **Creates GitHub Release**:
   - Attaches all build artifacts
   - Generates release notes from commits
   - Published automatically (not draft)

### 5. Monitor the Build

1. Go to GitHub repository
2. Click "Actions" tab
3. Watch the "Build Multi-Platform" workflow
4. Wait for all jobs to complete (typically 10-15 minutes)

### 6. Verify Release

Once the workflow completes:

1. Go to "Releases" page on GitHub
2. Find your new release (e.g., `v1.2.0`)
3. Verify all files are attached:
   - `BPB-Automation-Android-Universal.apk`
   - `BPB-Automation-macOS.dmg`
   - `BPB-Automation-Linux-x64.tar.gz`
   - `BPB-Automation-Windows-x64.zip`
4. Edit release notes if needed (auto-generated from commits)

### 7. Announce Release (Optional)

- Update project README with latest version
- Post on social media/forums if applicable
- Notify users through appropriate channels

## Build Artifacts

### Android APK
- **File**: `BPB-Automation-Android-Universal.apk`
- **Target**: Android 5.0+ (API 21+)
- **Architecture**: Universal (arm64-v8a, armeabi-v7a, x86_64)
- **Size**: ~25-35 MB
- **Distribution**: Direct download (sideload), no Play Store

### macOS DMG
- **File**: `BPB-Automation-macOS.dmg`
- **Target**: macOS 10.14+
- **Architecture**: Universal (Intel + Apple Silicon)
- **Size**: ~30-40 MB
- **Distribution**: Direct download, drag-and-drop install

### Linux tar.gz
- **File**: `BPB-Automation-Linux-x64.tar.gz`
- **Target**: Ubuntu 18.04+, other Linux distros with GTK3
- **Architecture**: x64
- **Size**: ~25-35 MB
- **Distribution**: Extract and run

### Windows ZIP
- **File**: `BPB-Automation-Windows-x64.zip`
- **Target**: Windows 10+
- **Architecture**: x64
- **Size**: ~20-30 MB
- **Distribution**: Extract and run .exe

## Troubleshooting Releases

### Build Fails on GitHub Actions

**Check the workflow logs**:
1. Go to Actions tab
2. Click on failed workflow
3. Expand failed job
4. Read error messages

**Common issues**:
- Flutter version mismatch: Update Flutter version in `.github/workflows/build.yml`
- Dependency issues: Run `flutter pub get` locally first
- Platform-specific build errors: Test local builds before tagging

### Release Not Created

**Possible causes**:
- Tag doesn't start with `v` (must be `v1.2.0`, not `1.2.0`)
- Build jobs failed (check Actions tab)
- GitHub token permissions (should auto-work)

**Fix**:
```bash
# Delete bad tag locally and remotely
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# Create new tag and push
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0
```

### Artifacts Missing

If some platform artifacts are missing:
1. Check which build job failed
2. Fix the issue in code
3. Delete the release and tag
4. Create new release with incremented version

## Quick Release Commands

```bash
# 1. Update version in pubspec.yaml manually, then:
git add pubspec.yaml
git commit -m "Bump version to 1.2.0+6"

# 2. Create and push tag
git tag -a v1.2.0 -m "Release v1.2.0: Add adaptive icons"
git push origin main && git push origin v1.2.0

# 3. Monitor at: https://github.com/YOUR_USERNAME/bpb-automation/actions
```

## Release Naming Convention

Use semantic versioning with descriptive messages:

```bash
# Feature release
git tag -a v1.2.0 -m "Release v1.2.0: Add adaptive app icons"

# Bug fix release
git tag -a v1.2.1 -m "Release v1.2.1: Fix icon display on Android"

# Major release
git tag -a v2.0.0 -m "Release v2.0.0: Complete UI redesign"
```

## Post-Release Tasks

After a successful release:

- [ ] Test downloaded artifacts on real devices
- [ ] Update documentation if needed
- [ ] Monitor for user-reported issues
- [ ] Plan next release features

## Rollback a Release

If you need to rollback:

```bash
# 1. Delete the GitHub release (via web UI)

# 2. Delete the tag
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# 3. Revert commits if needed
git revert HEAD
git push origin main
```

## Tips

- **Test locally first**: Always build and test locally before pushing tags
- **Small, frequent releases**: Better than large, infrequent ones
- **Clear commit messages**: They become release notes
- **Version consistency**: Keep version in sync across pubspec.yaml and tags
- **Backup keystore**: For Android signing (if implemented)

## Support

For issues with the release process:
- Check GitHub Actions logs
- Review this documentation
- Test builds locally to isolate issues
