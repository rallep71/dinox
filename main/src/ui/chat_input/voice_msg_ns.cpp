/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * Lightweight noise suppression for voice message recording.
 * Uses webrtc-audio-processing-2 with NS + High Pass Filter only (no AEC).
 * Processes 48kHz mono S16LE audio in 10ms chunks (480 samples).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#include <cstring>
#include <glib.h>
#include <gst/gst.h>

#ifdef WITH_VOICE_PROCESSOR
#include <modules/audio_processing/include/audio_processing.h>

#define NS_SAMPLE_RATE 48000
#define NS_CHANNELS 1
#define NS_FRAME_SAMPLES 480  // 10ms at 48kHz

struct VoiceMsgNS {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    int16_t leftover[NS_FRAME_SAMPLES];
    int leftover_count;
};

extern "C" void* dino_voice_msg_ns_init(void) {
    auto *ns = new VoiceMsgNS();
    ns->leftover_count = 0;

    rtc::scoped_refptr<webrtc::AudioProcessing> apm = webrtc::AudioProcessingBuilder().Create();

    webrtc::AudioProcessing::Config config;

    // No echo cancellation needed for voice messages
    config.echo_canceller.enabled = false;

    // Noise suppression at moderate level (kHigh causes artifacts with close-mic recording)
    config.noise_suppression.enabled = true;
    config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kModerate;

    // High-pass filter to remove DC offset and low-frequency rumble
    config.high_pass_filter.enabled = true;

    // Transient suppression off (audiodynamic compressor handles this)
    config.transient_suppression.enabled = false;

    // No AGC — we use external volume(1.5) + audiodynamic compressor instead.
    // Having AGC here causes gain pumping (wobbling) when combined with external gain stages.
    config.gain_controller1.enabled = false;
    config.gain_controller2.enabled = false;

    apm->ApplyConfig(config);
    ns->apm = apm;

    g_debug("voice_msg_ns: initialized (NS=kModerate, HPF=on, no AGC/TS)");
    return ns;
}

extern "C" void dino_voice_msg_ns_process(void *handle, int16_t *data, int num_samples) {
    if (!handle || !data || num_samples <= 0) return;

    auto *ns = (VoiceMsgNS *)handle;
    webrtc::StreamConfig stream_config(NS_SAMPLE_RATE, NS_CHANNELS);

    int pos = 0;

    // If we have leftover from previous call, prepend it
    if (ns->leftover_count > 0) {
        int needed = NS_FRAME_SAMPLES - ns->leftover_count;
        if (needed > num_samples) {
            // Not enough data to complete a frame, just accumulate
            memcpy(ns->leftover + ns->leftover_count, data, num_samples * sizeof(int16_t));
            ns->leftover_count += num_samples;
            return;
        }
        // Complete the leftover frame
        int16_t frame[NS_FRAME_SAMPLES];
        memcpy(frame, ns->leftover, ns->leftover_count * sizeof(int16_t));
        memcpy(frame + ns->leftover_count, data, needed * sizeof(int16_t));

        ns->apm->set_stream_delay_ms(0);
        int err = ns->apm->ProcessStream(frame, stream_config, stream_config, frame);
        if (err < 0) g_warning("voice_msg_ns: ProcessStream error %d", err);

        // Copy processed leftover part back (only the part that came from current data)
        memcpy(data, frame + ns->leftover_count, needed * sizeof(int16_t));
        // The leftover part was from previous buffer, we can't write it back there.
        // This is a minor imperfection (~10ms worth) but acceptable for voice messages.
        pos = needed;
        ns->leftover_count = 0;
    }

    // Process complete 10ms frames
    while (pos + NS_FRAME_SAMPLES <= num_samples) {
        ns->apm->set_stream_delay_ms(0);
        int err = ns->apm->ProcessStream(data + pos, stream_config, stream_config, data + pos);
        if (err < 0) g_warning("voice_msg_ns: ProcessStream error %d", err);
        pos += NS_FRAME_SAMPLES;
    }

    // Save leftover for next call
    int remaining = num_samples - pos;
    if (remaining > 0) {
        memcpy(ns->leftover, data + pos, remaining * sizeof(int16_t));
        ns->leftover_count = remaining;
    }
}

extern "C" void dino_voice_msg_ns_destroy(void *handle) {
    if (!handle) return;
    auto *ns = (VoiceMsgNS *)handle;
    ns->apm = nullptr;
    delete ns;
    g_debug("voice_msg_ns: destroyed");
}

// GStreamer pad probe callback — processes S16LE buffers through NS in-place.
// This MUST be in C/C++ because Vala's info.get_buffer() adds a ref,
// making the buffer non-writable and corrupting the pipeline.
static GstPadProbeReturn
ns_pad_probe_cb(GstPad *pad, GstPadProbeInfo *info, gpointer user_data) {
    (void)pad;
    VoiceMsgNS *ns = (VoiceMsgNS *)user_data;
    if (!ns) return GST_PAD_PROBE_OK;

    GstBuffer *buf = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!buf) return GST_PAD_PROBE_OK;

    // Make buffer writable (copies if refcount > 1)
    buf = gst_buffer_make_writable(buf);
    GST_PAD_PROBE_INFO_DATA(info) = buf;

    GstMapInfo map;
    if (gst_buffer_map(buf, &map, GST_MAP_READWRITE)) {
        int num_samples = (int)(map.size / sizeof(int16_t));
        dino_voice_msg_ns_process(ns, (int16_t *)map.data, num_samples);
        gst_buffer_unmap(buf, &map);
    }

    return GST_PAD_PROBE_OK;
}

extern "C" gulong dino_voice_msg_ns_install_probe(void *handle, GstElement *element) {
    if (!handle || !element) return 0;
    GstPad *src_pad = gst_element_get_static_pad(element, "src");
    if (!src_pad) return 0;
    gulong id = gst_pad_add_probe(src_pad, GST_PAD_PROBE_TYPE_BUFFER,
                                   ns_pad_probe_cb, handle, NULL);
    gst_object_unref(src_pad);
    g_debug("voice_msg_ns: pad probe installed (id=%lu)", id);
    return id;
}

#else
// Stub implementations when webrtc-audio-processing is not available
extern "C" void* dino_voice_msg_ns_init(void) {
    g_info("voice_msg_ns: webrtc-audio-processing not available, NS disabled");
    return NULL;
}

extern "C" void dino_voice_msg_ns_process(void *handle, int16_t *data, int num_samples) {
    (void)handle; (void)data; (void)num_samples;
}

extern "C" void dino_voice_msg_ns_destroy(void *handle) {
    (void)handle;
}

extern "C" gulong dino_voice_msg_ns_install_probe(void *handle, GstElement *element) {
    (void)handle; (void)element;
    return 0;
}
#endif
