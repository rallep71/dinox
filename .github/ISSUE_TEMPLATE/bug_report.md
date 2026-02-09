---
name: Bug Report
about: Report a bug or crash in DinoX
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

<!-- A clear and concise description of what the bug is -->

## Steps to Reproduce

1. Go to '...'
2. Click on '...'
3. Scroll down to '...'
4. See error

## Expected Behavior

<!-- What you expected to happen -->

## Actual Behavior

<!-- What actually happened -->

## Screenshots

<!-- If applicable, add screenshots to help explain your problem -->

## Environment

**DinoX Version**: 
<!-- Run: ./build/main/dinox --version -->
<!-- Or check About dialog -->

**OS**: 
<!-- e.g., Ubuntu 24.04, Arch Linux, Fedora 40, Windows 10/11 -->

**Installation Method**:
- [ ] Compiled from source
- [ ] Flatpak
- [ ] AppImage
- [ ] Windows (ZIP)
- [ ] AppMan / AM

**Desktop Environment**:
<!-- e.g., GNOME 47, KDE Plasma 6, etc. -->

## Logs

<details>
<summary>Click to expand logs</summary>

```
<!-- Paste logs here -->
<!-- Run with: DINO_LOG_LEVEL=debug ./build/main/dinox 2>&1 | tee dinox.log -->
<!-- Or Flatpak: flatpak run --env=DINO_LOG_LEVEL=debug im.github.rallep71.DinoX 2>&1 | tee dinox.log -->
<!-- Or Windows: set DINO_LOG_LEVEL=debug && dinox.exe > dinox.log 2>&1 -->
```

</details>

## Additional Context

<!-- Any other context about the problem here -->

## Checklist

- [ ] I have searched existing issues
- [ ] I am using the latest version
- [ ] I have included logs
- [ ] I have included reproduction steps
