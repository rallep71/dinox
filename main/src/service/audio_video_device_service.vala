using Gst;
using Gee;

namespace Dino.Ui {

public class DeviceInfo : GLib.Object {
    public string display_name { get; set; }
    public string detail_name { get; set; }
    public string protocol { get; set; default = ""; }
    public bool is_default { get; set; default = false; }
    public Gst.Device? gst_device { get; set; }
}

public class AudioVideoDeviceService : GLib.Object {

    public signal void devices_changed();

    private ArrayList<DeviceInfo> audio_inputs = new ArrayList<DeviceInfo>();
    private ArrayList<DeviceInfo> audio_outputs = new ArrayList<DeviceInfo>();
    private ArrayList<DeviceInfo> video_inputs = new ArrayList<DeviceInfo>();

    private Gst.DeviceMonitor? monitor;
    private uint bus_watch_id = 0;
    private bool started = false;

    public AudioVideoDeviceService() {
        start_monitor();
    }

    ~AudioVideoDeviceService() {
        stop_monitor();
    }

    private void start_monitor() {
        if (started) return;

        monitor = new Gst.DeviceMonitor();
        monitor.add_filter("Audio/Source", null);
        monitor.add_filter("Audio/Sink", null);
        monitor.add_filter("Video/Source", null);

        var bus = monitor.get_bus();
        bus_watch_id = bus.add_watch(Priority.DEFAULT, on_bus_message);

        started = monitor.start();
        if (started) {
            refresh_device_lists();
        } else {
            warning("AudioVideoDeviceService: Failed to start DeviceMonitor");
        }
    }

    private void stop_monitor() {
        if (bus_watch_id != 0) {
            Source.remove(bus_watch_id);
            bus_watch_id = 0;
        }
        if (monitor != null && started) {
            monitor.stop();
            started = false;
        }
        monitor = null;
    }

    private bool on_bus_message(Gst.Bus bus, Gst.Message message) {
        switch (message.type) {
            case Gst.MessageType.DEVICE_ADDED:
            case Gst.MessageType.DEVICE_REMOVED:
            case Gst.MessageType.DEVICE_CHANGED:
                refresh_device_lists();
                devices_changed();
                break;
            default:
                break;
        }
        return true;
    }

    private void refresh_device_lists() {
        if (monitor == null) return;

        var new_audio_in = new ArrayList<DeviceInfo>();
        var new_audio_out = new ArrayList<DeviceInfo>();
        var new_video_in = new ArrayList<DeviceInfo>();

        var seen_audio_in = new HashSet<string>();
        var seen_audio_out = new HashSet<string>();
        var seen_video_in = new HashSet<string>();

        foreach (Gst.Device device in monitor.get_devices()) {
            if (device.properties == null) continue;

            // Skip monitor/loopback devices
            if (device.properties.get_string("device.class") == "monitor") continue;

            string name = device.display_name;
            string protocol = get_protocol(device);

            if (device.has_classes("Audio") && device.has_classes("Source")) {
                // Skip PipeWire audio duplicates (prefer PulseAudio, same as RTP plugin)
                if (device.properties.has_name("pipewire-proplist")) continue;
                if (seen_audio_in.contains(name)) continue;
                seen_audio_in.add(name);
                new_audio_in.add(make_device_info(device, name, protocol));

            } else if (device.has_classes("Audio") && device.has_classes("Sink")) {
                if (device.properties.has_name("pipewire-proplist")) continue;
                if (seen_audio_out.contains(name)) continue;
                seen_audio_out.add(name);
                new_audio_out.add(make_device_info(device, name, protocol));

            } else if (device.has_classes("Video") && device.has_classes("Source")) {
                if (seen_video_in.contains(name)) continue;
                seen_video_in.add(name);
                new_video_in.add(make_device_info(device, name, protocol));
            }
        }

        audio_inputs = new_audio_in;
        audio_outputs = new_audio_out;
        video_inputs = new_video_in;
    }

    private DeviceInfo make_device_info(Gst.Device device, string name, string protocol) {
        var info = new DeviceInfo();
        info.display_name = name;
        info.detail_name = device.name;
        info.protocol = protocol;
        info.gst_device = device;

        bool is_default;
        if (device.properties.get_boolean("is-default", out is_default)) {
            info.is_default = is_default;
        }

        return info;
    }

    private string get_protocol(Gst.Device device) {
        if (device.properties.has_name("pulse-proplist")) return "pulseaudio";
        if (device.properties.has_name("pipewire-proplist")) return "pipewire";
        if (device.properties.has_name("v4l2deviceprovider")) return "v4l2";
        return "";
    }

    public Gee.List<DeviceInfo> get_audio_input_devices() {
        return audio_inputs.read_only_view;
    }

    public Gee.List<DeviceInfo> get_audio_output_devices() {
        return audio_outputs.read_only_view;
    }

    public Gee.List<DeviceInfo> get_video_input_devices() {
        return video_inputs.read_only_view;
    }

    public Gst.Element? create_audio_source(string device_name) {
#if WINDOWS
        return create_element_for(audio_inputs, device_name,
            {"wasapi2src", "autoaudiosrc"}, "audio-source");
#else
        return create_element_for(audio_inputs, device_name,
            {"autoaudiosrc"}, "audio-source");
#endif
    }

    public Gst.Element? create_audio_sink(string device_name) {
#if WINDOWS
        return create_element_for(audio_outputs, device_name,
            {"wasapi2sink", "autoaudiosink"}, "audio-sink");
#else
        return create_element_for(audio_outputs, device_name,
            {"autoaudiosink"}, "audio-sink");
#endif
    }

    public Gst.Element? create_video_source(string device_name) {
#if WINDOWS
        return create_element_for(video_inputs, device_name,
            {"mfvideosrc", "ksvideosrc", "autovideosrc"}, "video-source");
#else
        // Linux: pipewiresrc has higher rank and autovideosrc will pick it,
        // but try it explicitly first for systems where auto-detect fails.
        return create_element_for(video_inputs, device_name,
            {"autovideosrc", "pipewiresrc", "v4l2src"}, "video-source");
#endif
    }

    private Gst.Element? create_element_for(ArrayList<DeviceInfo> devices, string device_name,
                                              string[] fallback_factories, string element_name) {
        // 1. If a specific device was requested, find it by display_name
        if (device_name != "") {
            foreach (var info in devices) {
                if (info.display_name == device_name && info.gst_device != null) {
                    var element = info.gst_device.create_element(element_name);
                    if (element != null) return element;
                }
            }
            warning("AudioVideoDeviceService: Device '%s' not found, trying default device", device_name);
        }

        // 2. "System Default" or named device not found — use GstDevice for the default
        //    On Windows, bare factory elements (wasapi2src etc.) without device properties
        //    often fail. GstDevice.create_element() sets the device index/path automatically.
        foreach (var info in devices) {
            if (info.is_default && info.gst_device != null) {
                var element = info.gst_device.create_element(element_name);
                if (element != null) return element;
            }
        }
        // No default flag? Try the first available device.
        if (devices.size > 0 && devices[0].gst_device != null) {
            var element = devices[0].gst_device.create_element(element_name);
            if (element != null) return element;
        }

        // 3. Last resort: bare factory elements (works on Linux where auto* elements
        //    connect to the session's default device via PulseAudio/PipeWire)
        foreach (string factory in fallback_factories) {
            var element = Gst.ElementFactory.make(factory, element_name);
            if (element != null) return element;
        }
        return null;
    }

    public void rescan() {
        refresh_device_lists();
        devices_changed();
    }
}

}
