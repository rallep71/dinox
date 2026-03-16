/*
 * VAPI for WinRT Toast Notification helper.
 */

[CCode (cheader_filename = "toast_win32.h")]
namespace ToastWin32 {

    [CCode (cname = "ToastWin32ActivatedCallback", has_target = false)]
    public delegate void ActivatedCallback (string action_args, void* user_data);

    [CCode (cname = "toast_win32_init")]
    public static bool init (string app_name,
                             string aumid,
                             ActivatedCallback? callback,
                             void* user_data);

    [CCode (cname = "toast_win32_show")]
    public static void show (string xml_utf8, string? tag);

    [CCode (cname = "toast_win32_hide")]
    public static void hide (string tag);

    [CCode (cname = "toast_win32_cleanup")]
    public static void cleanup ();
}
