using GLib;

namespace Dino.Ui {

    public class LocationManager : Object {
        private static LocationManager? instance;
        
        public static LocationManager get_default() {
            if (instance == null) {
                instance = new LocationManager();
            }
            return instance;
        }

        private LocationManager() {}

        public async void get_location(Cancellable? cancellable, out double lat, out double lon, out double accuracy) throws Error {
            // Dummy für Windows
            lat = 0;
            lon = 0;
            accuracy = 0;
            
            // Einfach Fehler werfen, damit die UI weiß, dass es nicht geht.
            throw new IOError.NOT_SUPPORTED("Standortdienste sind unter Windows noch nicht verfügbar.");
        }
    }
}
