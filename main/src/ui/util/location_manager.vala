using GLib;

namespace Dino.Ui {

[DBus (name = "org.freedesktop.GeoClue2.Manager")]
interface GeoClueManager : Object {
    public abstract async ObjectPath get_client() throws Error;
}

[DBus (name = "org.freedesktop.GeoClue2.Client")]
interface GeoClueClient : Object {
    public abstract string desktop_id { set; }
    public abstract uint distance_threshold { set; }
    public abstract uint time_threshold { set; }
    public abstract uint requested_accuracy_level { set; }
    public abstract ObjectPath location { owned get; }
    public abstract async void start() throws Error;
    public abstract async void stop() throws Error;
    public signal void location_updated(ObjectPath old_path, ObjectPath new_path);
}

[DBus (name = "org.freedesktop.GeoClue2.Location")]
interface GeoClueLocation : Object {
    public abstract double latitude { get; }
    public abstract double longitude { get; }
    public abstract double accuracy { get; }
}

public class LocationManager : Object {
    private static LocationManager? instance;
    private GeoClueClient? client;
    private GeoClueManager? manager;
    
    public static LocationManager get_default() {
        if (instance == null) {
            instance = new LocationManager();
        }
        return instance;
    }

    private LocationManager() {}

    public async void get_location(Cancellable? cancellable, out double lat, out double lon, out double accuracy) throws Error {
        debug("LocationManager: Requesting location...");
        var app = (Dino.Ui.Application) GLib.Application.get_default();
        if (!app.settings.location_sharing_enabled) {
            debug("LocationManager: Location sharing disabled in settings");
            throw new IOError.PERMISSION_DENIED("Location sharing is disabled in settings");
        }

        if (manager == null) {
            debug("LocationManager: Connecting to GeoClue Manager...");
            manager = yield Bus.get_proxy(BusType.SYSTEM, "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager");
        }

        if (client == null) {
            debug("LocationManager: Creating GeoClue Client...");
            ObjectPath client_path = yield manager.get_client();
            debug("LocationManager: Client path: %s", client_path.to_string());
            client = yield Bus.get_proxy(BusType.SYSTEM, "org.freedesktop.GeoClue2", client_path.to_string());
            client.desktop_id = "im.github.rallep71.DinoX";
            client.distance_threshold = 0;
            client.time_threshold = 0;
            client.requested_accuracy_level = 8; // Exact
        }

        debug("LocationManager: Starting client...");
        yield client.start();

        ObjectPath loc_path = client.location;
        debug("LocationManager: Initial location path: %s", loc_path.to_string());
        
        if (loc_path.to_string() == "/") {
            debug("LocationManager: Waiting for location update...");
            var loop = new MainLoop();
            uint timeout_id = 0;
            
            ulong handler_id = client.location_updated.connect((o, n) => {
                debug("LocationManager: Location updated: %s", n.to_string());
                loc_path = n;
                if (timeout_id > 0) {
                    Source.remove(timeout_id);
                    timeout_id = 0;
                }
                loop.quit();
            });
            
            // Increase timeout to 45 seconds to allow for GPS/Wi-Fi fix
            timeout_id = Timeout.add_seconds(45, () => {
                debug("LocationManager: Timeout reached!");
                timeout_id = 0;
                loop.quit();
                return false;
            });
            
            loop.run();
            client.disconnect(handler_id);
            
            if (loc_path.to_string() == "/") {
                debug("LocationManager: Failed to get location (timeout)");
                yield client.stop();
                throw new IOError.TIMED_OUT("Timeout waiting for location service");
            }
        }
        
        debug("LocationManager: Retrieving location details from %s", loc_path.to_string());
        GeoClueLocation loc = yield Bus.get_proxy(BusType.SYSTEM, "org.freedesktop.GeoClue2", loc_path.to_string());
        
        lat = loc.latitude;
        lon = loc.longitude;
        accuracy = loc.accuracy;
        debug("LocationManager: Got location: %f, %f (acc: %f)", lat, lon, accuracy);
        
        yield client.stop();
    }
}

}
