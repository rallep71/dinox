/*
 * VAPI for manual SNI D-Bus registration with IconPixmap support.
 */

[CCode (cheader_filename = "systray_sni_dbus.h")]
namespace SniDbus {
    [CCode (cname = "SniGetPropertyFunc", has_target = false)]
    public delegate GLib.Variant? GetPropertyFunc (string property_name,
                                                    void* user_data);

    [CCode (cname = "SniMethodCallFunc", has_target = false)]
    public delegate void MethodCallFunc (string method_name,
                                          GLib.Variant parameters,
                                          GLib.DBusMethodInvocation invocation,
                                          void* user_data);

    [CCode (cname = "sni_dbus_register")]
    public static uint register (GLib.DBusConnection connection,
                                  string object_path,
                                  GetPropertyFunc get_property,
                                  MethodCallFunc method_call,
                                  void* user_data) throws GLib.Error;

    [CCode (cname = "sni_dbus_emit_signal")]
    public static void emit_signal (GLib.DBusConnection connection,
                                     string object_path,
                                     string signal_name,
                                     GLib.Variant? parameters = null);
}
