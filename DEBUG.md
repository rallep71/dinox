# Debug Mode

## Running DinoX with Debug Logging

### From Build Directory

```bash
DINO_LOG_LEVEL=debug ./build/main/dinox
```

### Full-Debug Call Logs (Recommended)

For reproducible audio/video call debugging, use the helper scripts in `scripts/`.
They make sure we always:

- write a unique log file under `logs/`
- store the correct DinoX PID (so stopping works reliably)
- keep a pointer to the latest log

#### Start full-debug logging

```bash
scripts/run-dinox-debug.sh
```

This prints (and writes):

- `logs/dinox.pid` → PID of `./build/main/dinox`
- `logs/dinox-runinfo-latest.txt` → path to the newest log file

Optional overrides:

```bash
GST_DEBUG=5 scripts/run-dinox-debug.sh
G_MESSAGES_DEBUG=all scripts/run-dinox-debug.sh
```

If DinoX is already running and you want to restart it:

```bash
scripts/run-dinox-debug.sh --restart
```

#### Stop full-debug logging

```bash
scripts/stop-dinox.sh
```

This sends `SIGINT` first (clean shutdown) and falls back to `SIGTERM` if needed.

#### Quick scan of the latest log

```bash
scripts/scan-dinox-latest-log.sh
```

This searches the latest log for:

- warnings/errors
- audio underflows / discontinuities
- ICE/DTLS startup buffering
- libnice TURN refresh warnings

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
