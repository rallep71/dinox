# DinoX Audio/Video Subsystem Recovery Plan

## 1. Situation Assessment
We have successfully stabilized the network transport layer (SRTP/Encryption), but the media processing layer (GStreamer/Audio) has degraded.

**Current Symptoms:**
- **Instability:** `GStreamer-CRITICAL` refcount errors (double-freeing memory).
- **Device Control:** Application ignores user microphone selection (defaults to Webcam).
- **Quality:** Severe Echo (AEC failure) despite previous fixes.
- **System Conflict:** Ambiguity between ALSA, PulseAudio, and PipeWire interactions.

## 2. Technical Analysis

### A. The "Backend" Problem (Device Selection)
Currently, DinoX likely relies on `autoaudiosrc` or similar GStreamer elements which delegate device selection to the OS. On a system with multiple sound servers (Mint often runs PulseAudio on top of ALSA, or PipeWire emulating Pulse), this is unreliable.

**The Solution: Explicit Device Management**
We need to move away from "magic" auto-selection.
1.  **Backend Logic:** We must implement a strict `DeviceBackend` that explicitly enumerates devices using `Gst.DeviceMonitor`.
2.  **Persistence:** The selected device ID (e.g., `alsa_input.usb-Logitech_Webcam...`) must be saved in the database/config.
3.  **Pipeline Construction:** When starting a call, we must instantiate a specific source (e.g., `pulsesrc device=...`) instead of generic sources.

### B. The Crash (GStreamer Memory Management)
The error `gst_mini_object_unref: assertion > 0 failed` in `VoiceProcessor.transform_ip` confirms a memory ownership violation.
- **Cause:** `transform_ip` is an "In-Place" transform. The buffer is passed to us, we process it, and pass it along.
- **The Bug:** We are pushing the buffer into an `Adapter` (for AEC analysis). `Adapter.push()` takes ownership. If we give the Adapter the buffer, we cannot also pass it down the pipeline unless we reference it correctly. The previous fix attempting `.ref()` caused a freeze because of type casting issues or blocking locks.

### C. Echo Cancellation (AEC)
AEC requires two aligned audio streams:
1.  **mic_signal:** What the microphone hears (Voice + Echo).
2.  **reverse_feed:** What is being played out the speakers (The Echo source).

If these two are not perfectly synchronized (within <50ms), AEC fails. The logs show "Delay adjusted..." constantly, implying the system is struggling to match the timing. Changing input devices (Webcam vs. Headset) changes latency, throwing off the AEC.

---

## 3. Implementation Roadmap

### Phase 1: Stabilization (Stop the Crashes)
We must fix `VoiceProcessor.vala` correctly.
- **Strategy:** Instead of pushing the *pipeline's* buffer into the adapter directly, we should map the buffer, copy the raw data, and push the *copy* into the adapter. This decouples the AEC analysis from the real-time audio path, preventing crashes and blocks.

### Phase 2: Explicit Audio Backend
We need to check `plugins/rtp/src/device.vala`.
- **Action:** Replace `autoaudiosrc` usage with specific GStreamer factory calls that accept a `device` parameter.
- **UI:** A dedicated "Audio/Video Settings" dialog that allows testing the microphone (VU Meter) *before* a call is made.

### Phase 3: Echo Tuning
Once we can reliably pick the specific microphone, we can tune the AEC.
- **Action:** Force a specific latency on the pipeline based on the selected backend (PulseAudio usually needs ~20-40ms latency configuration).

---

## 4. Immediate Action Item for User
I will now attempt to fix the **Phase 1 (Crash)** issue by safely copying data to the adapter instead of fighting with GStreamer refcounts. This should stop the crashes and restore audio, allowing us to tackle the Microphone selection issue next.
