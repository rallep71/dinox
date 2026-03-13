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
            lat = 0;
            lon = 0;
            accuracy = 0;

#if HAVE_GEOCLUE
            var simple = yield new GClue.Simple("im.github.rallep71.DinoX", GClue.AccuracyLevel.EXACT, cancellable);
            var location = simple.get_location();
            lat = location.latitude;
            lon = location.longitude;
            accuracy = location.accuracy;
            debug("LocationManager: GeoClue2 returned %.6f, %.6f (accuracy: %.0f m)", lat, lon, accuracy);
#else
            throw new IOError.NOT_SUPPORTED(_("Location services are not available (GeoClue2 not installed)."));
#endif
        }

        public bool is_available() {
#if HAVE_GEOCLUE
            return true;
#else
            return false;
#endif
        }
    }
}
