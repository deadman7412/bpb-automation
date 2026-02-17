# Release Guide

Complete guide for creating and managing releases for BPB Automation.

## Table of Contents

- [Creating a New Release](#creating-a-new-release)
- [Version Numbering](#version-numbering)
- [Release Artifacts](#release-artifacts)
- [Troubleshooting Failed Releases](#troubleshooting-failed-releases)
- [Emergency Rollback](#emergency-rollback)

## Creating a New Release

### Step 1: Update Version Number

Edit `pubspec.yaml` and update the version number:

```yaml
version: 2.2.0+1  # Format: MAJOR.MINOR.PATCH+BUILD
```

**Version Format:**
- `MAJOR`: Breaking changes (1.0.0 → 2.0.0)
- `MINOR`: New features, backward compatible (2.1.0 → 2.2.0)
- `PATCH`: Bug fixes, backward compatible (2.1.0 → 2.1.1)
- `BUILD`: Build number, increments with each build (+1, +2, +3)

### Step 2: Commit Changes

Commit with version prefix in message:

```bash
git add pubspec.yaml
git commit -m "v2.2.0: Add your feature description here"
git push origin main
```

**Commit Message Format:**
```
v{VERSION}: {DESCRIPTION}

Examples:
- v2.1.0: Add version numbers to all build artifacts
- v2.2.0: Implement scheduled auto-scans feature
- v2.1.1: Fix Cloudflare API timeout handling
```

### Step 3: Create and Push Tag

```bash
# Create annotated tag (recommended)
git tag -a v2.2.0 -m "Release version 2.2.0"

# Or create lightweight tag
git tag v2.2.0

# Push tag to GitHub
git push origin v2.2.0
```

### Step 4: Wait for Build

1. Go to: `https://github.com/YOUR_USERNAME/bpb-automation/actions`
2. Monitor the workflow run
3. Wait for all builds to complete (Android, macOS, Linux, Windows)
4. Check for any errors

### Step 5: Verify Release

1. Go to: `https://github.com/YOUR_USERNAME/bpb-automation/releases`
2. Find the new release (e.g., `v2.2.0`)
3. Verify all artifacts are attached:
   - `BPB-Automation-Android-Universal-2.2.0.apk`
   - `BPB-Automation-macOS-2.2.0.dmg`
   - `BPB-Automation-Linux-x64-2.2.0.tar.gz`
   - `BPB-Automation-Linux-x64-2.2.0.deb`
   - `BPB-Automation-Linux-x64-2.2.0.rpm`
   - `BPB-Automation-Windows-x64-2.2.0.zip`

## Version Numbering

### Semantic Versioning (SemVer)

We follow semantic versioning: `MAJOR.MINOR.PATCH`

**When to increment:**

- **MAJOR (2.0.0)** - Breaking changes:
  - API changes that break compatibility
  - Removed features
  - Major architecture changes
  - Example: `1.5.3` → `2.0.0`

- **MINOR (2.1.0)** - New features (backward compatible):
  - New features
  - Enhancements to existing features
  - New platforms supported
  - Example: `2.0.5` → `2.1.0`

- **PATCH (2.1.1)** - Bug fixes (backward compatible):
  - Bug fixes
  - Performance improvements
  - Documentation updates
  - Example: `2.1.0` → `2.1.1`

### Build Number

The build number (`+1`, `+2`, etc.) is used internally by Flutter and increments with each build:

```yaml
version: 2.1.0+1   # First build of 2.1.0
version: 2.1.0+2   # Second build of 2.1.0 (rebuild/hotfix)
version: 2.1.1+1   # First build of 2.1.1
```

**Note:** Build number is NOT shown in release filenames, only the semantic version is used.

## Release Artifacts

Each release includes the following artifacts:

| Platform | Format | Filename Pattern | Size (approx) |
|----------|--------|------------------|---------------|
| Android | APK (Universal) | `BPB-Automation-Android-Universal-{VERSION}.apk` | ~118 MB |
| macOS | DMG | `BPB-Automation-macOS-{VERSION}.dmg` | ~113 MB |
| Linux | tar.gz | `BPB-Automation-Linux-x64-{VERSION}.tar.gz` | ~67 MB |
| Linux | .deb (Ubuntu/Debian) | `BPB-Automation-Linux-x64-{VERSION}.deb` | ~67 MB |
| Linux | .rpm (Fedora/RHEL) | `BPB-Automation-Linux-x64-{VERSION}.rpm` | ~67 MB |
| Windows | ZIP | `BPB-Automation-Windows-x64-{VERSION}.zip` | ~45 MB |

**Note:** Debug builds are not included in releases. Only production-ready release builds are distributed.

## Troubleshooting Failed Releases

### Scenario 1: Build Failed After Pushing Tag

**Problem:** You pushed a tag, but the GitHub Actions build failed.

**Solution:**

1. **Check the error logs:**
   ```bash
   # Go to GitHub Actions
   https://github.com/YOUR_USERNAME/bpb-automation/actions
   
   # Click on the failed workflow
   # Read error messages
   ```

2. **Delete the tag (locally and remotely):**
   ```bash
   # Delete local tag
   git tag -d v2.2.0
   
   # Delete remote tag
   git push origin :refs/tags/v2.2.0
   ```

3. **Delete the draft release (if created):**
   - Go to: `https://github.com/YOUR_USERNAME/bpb-automation/releases`
   - Find the failed release
   - Click "Delete" button

4. **Fix the issue:**
   ```bash
   # Make necessary fixes
   git add .
   git commit -m "v2.2.0: Fix build issue - {description}"
   git push origin main
   ```

5. **Recreate the tag:**
   ```bash
   git tag -a v2.2.0 -m "Release version 2.2.0"
   git push origin v2.2.0
   ```

### Scenario 2: Wrong Version Number in Tag

**Problem:** You pushed `v2.2.0` but meant to push `v2.3.0`.

**Solution:**

1. **Delete the incorrect tag:**
   ```bash
   # Delete local tag
   git tag -d v2.2.0
   
   # Delete remote tag
   git push origin :refs/tags/v2.2.0
   ```

2. **Delete the release on GitHub:**
   - Go to releases page
   - Delete the incorrect release

3. **Update pubspec.yaml with correct version:**
   ```yaml
   version: 2.3.0+1
   ```

4. **Commit and create correct tag:**
   ```bash
   git add pubspec.yaml
   git commit -m "v2.3.0: Correct version number"
   git push origin main
   
   git tag -a v2.3.0 -m "Release version 2.3.0"
   git push origin v2.3.0
   ```

### Scenario 3: Partial Build Success (Some Platforms Failed)

**Problem:** Android and macOS built successfully, but Linux and Windows failed.

**Solution:**

1. **Check which platforms failed:**
   - Go to GitHub Actions
   - Identify failed jobs

2. **Option A: Delete and retry** (if critical):
   ```bash
   # Delete tag
   git tag -d v2.2.0
   git push origin :refs/tags/v2.2.0
   
   # Delete release
   # (Go to GitHub releases page and delete)
   
   # Fix the issue
   git add .
   git commit -m "v2.2.0: Fix Linux/Windows build"
   git push origin main
   
   # Recreate tag
   git tag -a v2.2.0 -m "Release version 2.2.0"
   git push origin v2.2.0
   ```

3. **Option B: Manual upload** (if minor):
   - Build the failed platforms locally
   - Manually upload to the existing release on GitHub

### Scenario 4: Release Created But Artifacts Missing

**Problem:** Release exists but some artifacts are missing.

**Solution:**

1. **Check workflow artifacts:**
   - Go to the workflow run
   - Download missing artifacts manually
   - Upload them to the release

2. **Or delete and retry:**
   ```bash
   # Delete tag and release (as shown above)
   # Recreate tag
   ```

## Emergency Rollback

### If a Released Version Has Critical Bugs

1. **Mark release as pre-release:**
   - Go to the release on GitHub
   - Click "Edit release"
   - Check "This is a pre-release"
   - Add warning in description

2. **Create hotfix version:**
   ```bash
   # Update version (patch increment)
   # In pubspec.yaml: 2.2.0+1 → 2.2.1+1
   
   git add pubspec.yaml
   git commit -m "v2.2.1: Critical hotfix - {description}"
   git push origin main
   
   git tag -a v2.2.1 -m "Hotfix release 2.2.1"
   git push origin v2.2.1
   ```

3. **Update README and docs** to point to new version

### Complete Tag/Release Deletion

If you need to completely remove a version:

```bash
# 1. Delete local tag
git tag -d v2.2.0

# 2. Delete remote tag
git push origin :refs/tags/v2.2.0

# Or alternative syntax:
git push --delete origin v2.2.0

# 3. Delete release on GitHub
# Go to: https://github.com/YOUR_USERNAME/bpb-automation/releases
# Click on the release
# Click "Delete" button at the bottom

# 4. Verify deletion
git tag -l
git ls-remote --tags origin
```

## Best Practices

### Before Releasing

- [ ] Update version in `pubspec.yaml`
- [ ] Run tests locally: `flutter test --exclude-tags=integration`
- [ ] Run analyzer: `flutter analyze`
- [ ] Update CHANGELOG.md with changes
- [ ] Test build on at least one platform
- [ ] Review all changes since last release

### During Release

- [ ] Use clear, descriptive commit messages
- [ ] Use annotated tags (include message)
- [ ] Monitor GitHub Actions workflow
- [ ] Wait for all platforms to complete

### After Release

- [ ] Verify all artifacts are present
- [ ] Test download and installation
- [ ] Update documentation if needed
- [ ] Announce release (if public)

## Common Commands Reference

```bash
# List all tags
git tag -l

# List remote tags
git ls-remote --tags origin

# View tag details
git show v2.2.0

# Delete local tag
git tag -d v2.2.0

# Delete remote tag (two methods)
git push origin :refs/tags/v2.2.0
git push --delete origin v2.2.0

# Create annotated tag
git tag -a v2.2.0 -m "Release message"

# Create lightweight tag
git tag v2.2.0

# Push specific tag
git push origin v2.2.0

# Push all tags
git push origin --tags

# View version from pubspec.yaml
grep '^version:' pubspec.yaml
```

## Automation Details

### How Version Extraction Works

The workflow automatically extracts the version from `pubspec.yaml`:

```bash
# Extracts: 2.1.0 from "version: 2.1.0+1"
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
```

This version is then used in all artifact filenames.

### Workflow Triggers

The release workflow (`create-release` job) only runs when:
- A tag matching `v*` pattern is pushed
- Example: `v1.0.0`, `v2.1.0`, `v2.2.1`

Regular commits to `main` branch will:
- Build all platforms
- Create artifacts
- Upload to GitHub Actions (30-day retention)
- **NOT** create a GitHub Release

## Support

If you encounter issues not covered here:

1. Check GitHub Actions logs for detailed error messages
2. Review the workflow file: `.github/workflows/build.yml`
3. Test builds locally before creating tags
4. Create an issue with error logs and steps to reproduce

## See Also

- [Development Guide](development.md) - For local development
- [Deployment Guide](deployment.md) - For platform-specific builds
- [User Guide](user-guide.md) - For end-user documentation
