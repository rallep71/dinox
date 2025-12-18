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

#### Flatpak: Audio debugging (GStreamer + sandbox)

If audio is missing (playback or microphone) in Flatpak builds, collect logs that show which GStreamer elements are chosen and whether PulseAudio/PipeWire is reachable.

```bash
flatpak run \
   --env=DINO_LOG_LEVEL=debug \
   --env=G_MESSAGES_DEBUG=all \
   --env=GST_DEBUG=2,pulse*:5,pipewire*:5,audiobasesink:5,audiobasesrc:5,webrtc*:4,rtp*:4 \
   im.github.rallep71.DinoX 2>&1 | tee /tmp/dinox-flatpak-audio.log
```

Quick checks inside the sandbox:

```bash
flatpak run --command=sh --devel im.github.rallep71.DinoX
# inside shell:
gst-inspect-1.0 autoaudiosink pulsesink pipewiresink 2>/dev/null | head -n 30
env | grep -E 'PULSE|PIPEWIRE|GST_'
```

### AppImage

```bash
DINO_LOG_LEVEL=debug ./DinoX-*.AppImage
```

#### AppImage: Audio debugging (GStreamer plugin discovery)

If AppImage builds have no sound, the most common causes are missing/broken GStreamer plugin discovery (sinks/sources not found) or missing runtime access to PulseAudio/PipeWire.

```bash
G_MESSAGES_DEBUG=all \
GST_DEBUG=2,pulse*:5,pipewire*:5,audiobasesink:5,audiobasesrc:5,webrtc*:4,rtp*:4 \
DINO_LOG_LEVEL=debug \
./DinoX-*.AppImage 2>&1 | tee /tmp/dinox-appimage-audio.log
```

Optional: verify what the AppImage bundles and which plugins are visible:

```bash
./DinoX-*.AppImage --appimage-extract >/dev/null
./squashfs-root/usr/bin/gst-inspect-1.0 autoaudiosink pulsesink pipewiresink 2>/dev/null | head -n 30
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
