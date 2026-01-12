namespace Dino {

[DBus (name = "org.freedesktop.login1.Manager")]
public interface Login1Manager : Object {
    public signal void PrepareForSleep(bool suspend);
}

public static async Login1Manager? get_login1() {
    try {
        return yield Bus.get_proxy(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
    } catch (IOError e) {
        warning("%s", e.message);
    }
    return null;
}

}
