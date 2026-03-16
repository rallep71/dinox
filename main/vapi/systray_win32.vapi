/*
 * VAPI for Win32 Shell_NotifyIcon systray helper.
 */

[CCode (cheader_filename = "systray_win32.h")]
namespace SystrayWin32 {

    [CCode (cname = "SystrayWin32Callback", has_target = false)]
    public delegate void Callback (int menu_id, void* user_data);

    [CCode (cname = "SystrayWin32BalloonCallback", has_target = false)]
    public delegate void BalloonCallback (void* user_data);

    [CCode (cname = "systray_win32_check_single_instance")]
    public static bool check_single_instance ();

    [CCode (cname = "systray_win32_init")]
    public static bool init (string tooltip,
                             int icon_resource_id,
                             Callback callback,
                             void* user_data);

    [CCode (cname = "systray_win32_set_menu")]
    public static void set_menu ([CCode (array_null_terminated = true, array_length = false)]
                                 string?[] labels,
                                 uint32 checked_mask);

    [CCode (cname = "systray_win32_set_tooltip")]
    public static void set_tooltip (string tooltip);

    [CCode (cname = "systray_win32_show_balloon")]
    public static void show_balloon (string title,
                                     string body,
                                     int icon_type,
                                     BalloonCallback? callback,
                                     void* user_data);

    [CCode (cname = "systray_win32_hide_balloon")]
    public static void hide_balloon ();

    [CCode (cname = "systray_win32_cleanup")]
    public static void cleanup ();
}
