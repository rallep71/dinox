# Debug Mode

## Running DinoX with Debug Logging

### From Build Directory

```bash
DINO_LOG_LEVEL=debug ./build/main/dinox
```

### Flatpak

```bash
flatpak run --env=DINO_LOG_LEVEL=debug im.github.rallep71.DinoX
```

### AppImage

```bash
DINO_LOG_LEVEL=debug ./DinoX-*.AppImage
```

## Log Levels

| Level | Description |
|-------|-------------|
| `error` | Only errors |
| `warning` | Errors and warnings |
| `info` | General information (default) |
| `debug` | Detailed debug output |

## GStreamer Debug (Audio/Video)

For audio/video call debugging:

```bash
GST_DEBUG=3 DINO_LOG_LEVEL=debug ./build/main/dinox
```

Higher GST_DEBUG levels (4-5) provide more detail but are very verbose.

## Common Issues

### Audio/Video Not Working

1. Check GStreamer plugins are installed:
   ```bash
   gst-inspect-1.0 webrtcdsp
   gst-inspect-1.0 nice
   gst-inspect-1.0 srtp
   ```

2. Run with GStreamer debug:
   ```bash
   GST_DEBUG=webrtc*:5 flatpak run im.github.rallep71.DinoX
   ```

### OMEMO Issues

Check OMEMO debug output:
```bash
DINO_LOG_LEVEL=debug flatpak run im.github.rallep71.DinoX 2>&1 | grep -i omemo
```

### Connection Issues

```bash
DINO_LOG_LEVEL=debug flatpak run im.github.rallep71.DinoX 2>&1 | grep -i "connection\|stream\|tls"
```

## Reporting Bugs

When reporting issues, please include:

1. DinoX version (`flatpak info im.github.rallep71.DinoX` or check About dialog)
2. Linux distribution and version
3. Relevant log output with `DINO_LOG_LEVEL=debug`
4. Steps to reproduce the issue

Submit issues at: https://github.com/rallep71/dinox/issues
