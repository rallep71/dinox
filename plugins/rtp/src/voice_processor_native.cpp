/*
 * Copyright (C) 2016-2025 Dino Team
 * Modifications Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#include <algorithm>
#include <gst/gst.h>
#include <gst/audio/audio.h>

#ifndef G_LOG_DOMAIN
#define G_LOG_DOMAIN "rtp"
#endif

#if defined(WEBRTC1) || defined(WEBRTC2)
#include <modules/audio_processing/include/audio_processing.h>
#else
#error "Need to define WEBRTC1 or WEBRTC2"
#endif

#define SAMPLE_RATE 48000
#define SAMPLE_CHANNELS 1

struct _DinoPluginsRtpVoiceProcessorNative {
    rtc::scoped_refptr<webrtc::AudioProcessing> apm;
    gint stream_delay = 0;
    gint last_median = 0;
    gint last_poor_delays = 0;
};

extern "C" void *dino_plugins_rtp_adjust_to_running_time(GstBaseTransform *transform, GstBuffer *buffer) {
    GstBuffer *copy = gst_buffer_copy(buffer);
    GST_BUFFER_PTS(copy) = gst_segment_to_running_time(&transform->segment, GST_FORMAT_TIME, GST_BUFFER_PTS(buffer));
    return copy;
}

extern "C" void *dino_plugins_rtp_voice_processor_init_native(gint stream_delay) {
    auto *native = new _DinoPluginsRtpVoiceProcessorNative();
    native->stream_delay = stream_delay;

    rtc::scoped_refptr<webrtc::AudioProcessing> apm = webrtc::AudioProcessingBuilder().Create();
    
    webrtc::AudioProcessing::Config config;
    config.echo_canceller.enabled = true;
    config.echo_canceller.mobile_mode = true;
    
    config.noise_suppression.enabled = true;
    config.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;
    
    config.gain_controller1.enabled = true;
    config.gain_controller1.mode = webrtc::AudioProcessing::Config::GainController1::kAdaptiveDigital;
    config.gain_controller1.target_level_dbfs = 3;
    config.gain_controller1.compression_gain_db = 9;
    config.gain_controller1.enable_limiter = true;
    
    config.high_pass_filter.enabled = true;
    
#ifdef WEBRTC1
    config.level_estimation.enabled = true;
    config.voice_detection.enabled = true;
#endif

    apm->ApplyConfig(config);
    native->apm = apm;

    g_debug("voice_processor_native.cpp: init (WEBRTC1/2): rate=%d channels=%d stream_delay=%dms aec=%d(mobile=%d) ns=%d(level=%d) agc=%d(mode=%d target=%d comp=%d) highpass=%d", \
            SAMPLE_RATE,
            SAMPLE_CHANNELS,
            native->stream_delay,
            (int) config.echo_canceller.enabled,
            (int) config.echo_canceller.mobile_mode,
            (int) config.noise_suppression.enabled,
            (int) config.noise_suppression.level,
            (int) config.gain_controller1.enabled,
            (int) config.gain_controller1.mode,
            (int) config.gain_controller1.target_level_dbfs,
            (int) config.gain_controller1.compression_gain_db,
            (int) config.high_pass_filter.enabled);

    return native;
}

extern "C" void
dino_plugins_rtp_voice_processor_analyze_reverse_stream(void *native_ptr, GstAudioInfo *info, GstBuffer *buffer) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    int err;

    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
#ifdef WEBRTC1
    webrtc::StreamConfig config(SAMPLE_RATE, SAMPLE_CHANNELS, false);
#else
    webrtc::StreamConfig config(SAMPLE_RATE, SAMPLE_CHANNELS);
#endif
    GstAudioBuffer abuf;
    if (!gst_audio_buffer_map (&abuf, info, buffer, GST_MAP_READWRITE)) {
        g_warning("voice_processor_native.cpp: analyze_reverse_stream: gst_audio_buffer_map failed");
        return;
    }

    apm->set_stream_delay_ms (native->stream_delay);
    auto * const data = (int16_t * const) abuf.planes[0];
    err = apm->ProcessReverseStream (data, config, config, data);

    gst_audio_buffer_unmap (&abuf);

    if (err < 0) g_warning("voice_processor_native.cpp: ProcessReverseStream %i", err);
}

extern "C" void dino_plugins_rtp_voice_processor_notify_gain_level(void *native_ptr, gint gain_level) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
    apm->set_stream_analog_level(gain_level);
}

extern "C" gint dino_plugins_rtp_voice_processor_get_suggested_gain_level(void *native_ptr) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    int level = 0;
    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
    level = apm->recommended_stream_analog_level();
    return level;
}

extern "C" bool dino_plugins_rtp_voice_processor_get_stream_has_voice(void *native_ptr) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    bool has_voice = false;
#if defined(WEBRTC1)
    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
    webrtc::AudioProcessingStats stats = apm->GetStatistics ();
    has_voice = stats.voice_detected.value_or(false);
#endif
    return has_voice;
}

extern "C" void dino_plugins_rtp_voice_processor_set_stream_delay(void *native_ptr, gint stream_delay) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    native->stream_delay = stream_delay;
}

extern "C" void dino_plugins_rtp_voice_processor_adjust_stream_delay(void *native_ptr) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    int median, std, poor_delays;
    float fraction_poor_delays;

    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
    webrtc::AudioProcessingStats stats = apm->GetStatistics();
    median = stats.delay_median_ms.value_or(-1);
    std = stats.delay_standard_deviation_ms.value_or(-1);
    fraction_poor_delays = (float) stats.divergent_filter_fraction.value_or(-1.0);
    poor_delays = (int) (fraction_poor_delays * 100.0);

    if (fraction_poor_delays < 0 || (native->last_median == median && native->last_poor_delays == poor_delays)) return;
    g_debug("voice_processor_native.cpp: Stream delay metrics: median=%i std=%i poor_delays=%i%%", median, std, poor_delays);
    native->last_median = median;
    native->last_poor_delays = poor_delays;
    if (poor_delays > 90 && median >= 0 - 384 && median <= 384) {
        // Adjust the configured stream delay slowly to help the AEC converge.
        // Clamp each step to +/-48ms and keep the delay within [0ms, 384ms].
        int delta = std::min(48, std::max(median, -48));
        native->stream_delay = std::min(std::max(0, native->stream_delay + delta), 384);
        g_debug("voice_processor_native.cpp: set stream_delay=%i", native->stream_delay);
    }
}

extern "C" void
dino_plugins_rtp_voice_processor_process_stream(void *native_ptr, GstAudioInfo *info, GstBuffer *buffer) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    int err;

    rtc::scoped_refptr<webrtc::AudioProcessing> apm = native->apm;
#ifdef WEBRTC1
    webrtc::StreamConfig config(SAMPLE_RATE, SAMPLE_CHANNELS, false);
#else
    webrtc::StreamConfig config(SAMPLE_RATE, SAMPLE_CHANNELS);
#endif
    GstAudioBuffer abuf;
    if (!gst_audio_buffer_map (&abuf, info, buffer, GST_MAP_READWRITE)) {
        g_warning("voice_processor_native.cpp: process_stream: gst_audio_buffer_map failed");
        return;
    }

    // Set stream delay for echo cancellation
    apm->set_stream_delay_ms(native->stream_delay);
    
    auto * const data = (int16_t * const) abuf.planes[0];
    err = apm->ProcessStream (data, config, config, data);

    gst_audio_buffer_unmap (&abuf);

    if (err < 0) g_warning("voice_processor_native.cpp: ProcessStream %i", err);
}

extern "C" void dino_plugins_rtp_voice_processor_destroy_native(void *native_ptr) {
    auto *native = (_DinoPluginsRtpVoiceProcessorNative *) native_ptr;
    native->apm = nullptr;
    delete native;
}
