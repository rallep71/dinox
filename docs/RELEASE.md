# 🚀 Release Guide for DinoX

This guide explains how to create releases for DinoX.

## 📋 Prerequisites

- Push access to the repository
- Clean git working directory (no uncommitted changes)
- On `master` branch (or specify a different branch)

## 🎯 Quick Release

### Option 1: Using the Release Script (Recommended)

```bash
# Create release v0.6.0
./scripts/release.sh 0.6.0
```

The script will:
1. ✅ Validate version format
2. ✅ Check for uncommitted changes
3. ✅ Update `CHANGELOG.md` with date
4. ✅ Create commit
5. ✅ Create annotated git tag
6. ✅ Push to GitHub
7. ✅ Trigger release workflow

### Option 2: Manual Process

```bash
# 1. Update CHANGELOG.md
# Replace [Unreleased] with [0.6.0] - 2025-11-21

# 2. Commit
git add CHANGELOG.md
git commit -m "chore: Release version 0.6.0"

# 3. Create tag
git tag -a v0.6.0 -m "Release Dino Extended v0.6.0"

# 5. Push
git push origin master
git push origin v0.6.0
```

## 📦 What Gets Built

The GitHub Actions workflow (`.github/workflows/release.yml`) automatically builds:

1. **Source Tarball** (`dino-extended-0.6.0.tar.gz`)
   - Full source code archive
   - SHA256 checksum included

2. **Flatpak Packages**
   - `dino-extended-0.6.0-x86_64.flatpak` (Intel/AMD)
   - `dino-extended-0.6.0-aarch64.flatpak` (ARM64)

3. **GitHub Release**
   - Release notes from CHANGELOG.md
   - All build artifacts attached
   - Installation instructions included

## 🔄 Versioning

We use [Semantic Versioning](https://semver.org/):

- **MAJOR** (0.x.0): Breaking changes, major new features
- **MINOR** (x.6.x): New features, non-breaking changes
- **PATCH** (x.x.1): Bug fixes, small improvements

### Examples

- `0.6.0` - First release with contact management
- `0.6.1` - Bug fix for blocking feature
- `0.7.0` - Add XEP-0424/0425 UI features
- `1.0.0` - Stable release, production-ready

## 📝 CHANGELOG.md Format

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [Unreleased]

### Added
- New features go here

### Fixed
- Bug fixes go here

### Changed
- Changes to existing features

### Removed
- Removed features

## [0.6.0] - 2025-11-21

### Added
- Feature 1
- Feature 2
```

## 🎯 Release Checklist

Before creating a release:

- [ ] All planned features are merged
- [ ] All tests pass (`meson test -C build`)
- [ ] Build is clean (0 errors, 0 warnings)
- [ ] CHANGELOG.md is updated with all changes
- [ ] Documentation is up to date
- [ ] No uncommitted changes

## 🔍 Monitoring the Release

After pushing the tag:

1. **GitHub Actions**: https://github.com/rallep71/dinox/actions
   - Watch the "Release" workflow
   - Usually takes 10-15 minutes
   - Builds for both x86_64 and aarch64

2. **Release Page**: https://github.com/rallep71/dinox/releases
   - Release appears automatically
   - All artifacts are uploaded
   - Users can download immediately

## 🐛 Troubleshooting

### Release workflow failed

Check the Actions tab for error messages:
- Build errors: Fix code and create new tag
- Upload errors: Usually permissions issue
- Flatpak errors: Check manifest dependencies

### Need to redo a release

```bash
# Delete local tag
git tag -d v0.6.0

# Delete remote tag
git push --delete origin v0.6.0

# Delete release on GitHub (via web UI)
# Then create new tag with same version
```

### Tag exists but no release

The workflow only triggers on tag push. If you created the tag locally:

```bash
# Push the tag
git push origin v0.6.0
```

## 🔐 Permissions

The release workflow uses `GITHUB_TOKEN` which is automatically provided by GitHub Actions. No additional secrets needed.

## 📊 Version History

See [CHANGELOG.md](../CHANGELOG.md) for full version history.

## 🔗 Links

- [GitHub Actions Workflow](../.github/workflows/release.yml)
- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
