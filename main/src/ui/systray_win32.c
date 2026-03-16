/*
 * Win32 Shell_NotifyIcon systray helper for DinoX.
 *
 * Creates a hidden message-only window to receive WM_APP tray callbacks,
 * uses Shell_NotifyIconW for the notification-area icon, and
 * CreatePopupMenu / TrackPopupMenu for the right-click context menu.
 *
 * All Win32 calls use the wide (W) variants.  UTF-8 ↔ UTF-16 conversion
 * is done via GLib's g_utf8_to_utf16().
 *
 * Thread safety: all functions must be called from the GTK main thread
 * (which owns the GDK Win32 display and message pump).
 */

#include "systray_win32.h"

#ifdef _WIN32

#include <windows.h>
#include <shellapi.h>
#include <stdarg.h>
#include <stdio.h>

/* Ensure definitions for older MinGW-w64 / SDK headers. */
#ifndef NOTIFYICON_VERSION_4
#define NOTIFYICON_VERSION_4  4
#endif
#ifndef NIN_SELECT
#define NIN_SELECT      (WM_USER + 0)
#endif
#ifndef NIN_KEYSELECT
#define NIN_KEYSELECT   (WM_USER + 1)
#endif
#ifndef NIF_SHOWTIP
#define NIF_SHOWTIP     0x00000080
#endif

#define WM_TRAYICON  (WM_APP + 1)
#define MAX_MENU_ITEMS 32

/* ---- state ---- */
static HWND            msg_hwnd   = NULL;
static NOTIFYICONDATAW nid        = {0};
static HMENU           popup_menu = NULL;
static gboolean        initialised = FALSE;

static SystrayWin32Callback user_callback = NULL;
static gpointer             user_data_ptr = NULL;

static SystrayWin32BalloonCallback balloon_callback = NULL;
static gpointer                     balloon_data_ptr = NULL;

static UINT            WM_TASKBARCREATED = 0;
static int             saved_icon_resource_id = 1;
static gboolean        using_version_4 = FALSE;
static FILE           *tray_log_file = NULL;

/* ---- debug log → %TEMP%/dinox_systray.log ---- */
static void
tray_log (const char *fmt, ...)
{
    va_list ap;
    va_start (ap, fmt);

    if (tray_log_file == NULL) {
        const char *tmp = g_get_tmp_dir ();
        char *path = g_build_filename (tmp, "dinox_systray.log", NULL);
        tray_log_file = fopen (path, "w");
        g_free (path);
        if (tray_log_file)
            fprintf (tray_log_file, "=== DinoX Systray Debug Log ===\n\n");
    }
    if (tray_log_file) {
        va_list copy;
        va_copy (copy, ap);
        vfprintf (tray_log_file, fmt, copy);
        va_end (copy);
        fprintf (tray_log_file, "\n");
        fflush (tray_log_file);
    }

    g_logv ("Systray", G_LOG_LEVEL_MESSAGE, fmt, ap);
    va_end (ap);
}

/* ---- forward ---- */
static LRESULT CALLBACK wnd_proc (HWND, UINT, WPARAM, LPARAM);

/* ---- helpers ---- */
static wchar_t *
utf8_to_wchar (const gchar *s)
{
    if (s == NULL) return NULL;
    glong len = 0;
    gunichar2 *w = g_utf8_to_utf16 (s, -1, NULL, &len, NULL);
    return (wchar_t *) w;
}

/* ---- public API ---- */

gboolean
systray_win32_init (const gchar          *tooltip_utf8,
                    int                   icon_resource_id,
                    SystrayWin32Callback  callback,
                    gpointer              user_data)
{
    if (initialised) return TRUE;

    user_callback  = callback;
    user_data_ptr  = user_data;

    /* Register a minimal window class for the tray callback window. */
    WNDCLASSEXW wc = {0};
    wc.cbSize        = sizeof (wc);
    wc.lpfnWndProc   = wnd_proc;
    wc.hInstance      = GetModuleHandleW (NULL);
    wc.lpszClassName  = L"DinoXSystrayMsg";
    RegisterClassExW (&wc);

    /* Use a normal hidden window (not HWND_MESSAGE) for better compatibility
     * with Windows 10/11 message dispatch.  WS_EX_TOOLWINDOW prevents a
     * taskbar entry; the 0×0 size keeps it invisible. */
    msg_hwnd = CreateWindowExW (WS_EX_TOOLWINDOW,
                                L"DinoXSystrayMsg", L"DinoX Tray",
                                WS_POPUP, 0, 0, 0, 0,
                                NULL, NULL,
                                GetModuleHandleW (NULL), NULL);
    if (msg_hwnd == NULL) {
        tray_log ("CreateWindowExW failed (error %lu)", GetLastError ());
        return FALSE;
    }

    saved_icon_resource_id = icon_resource_id;

    /* Register "TaskbarCreated" message — Explorer sends this after restart. */
    WM_TASKBARCREATED = RegisterWindowMessageW (L"TaskbarCreated");

    /* Load icon at the correct small-icon size for the notification area. */
    int cx = GetSystemMetrics (SM_CXSMICON);
    int cy = GetSystemMetrics (SM_CYSMICON);
    HICON icon = (HICON) LoadImageW (GetModuleHandleW (NULL),
                                      MAKEINTRESOURCEW (icon_resource_id),
                                      IMAGE_ICON, cx, cy, LR_DEFAULTCOLOR);
    if (icon == NULL) {
        /* Fallback: load at default size. */
        icon = LoadIconW (GetModuleHandleW (NULL),
                          MAKEINTRESOURCEW (icon_resource_id));
    }
    if (icon == NULL) {
        /* Last resort: standard application icon. */
        icon = LoadIconW (NULL, MAKEINTRESOURCEW (32512));
    }
    tray_log ("Icon loaded: %p (resource %d, size %dx%d)",
              (void *) icon, icon_resource_id, cx, cy);

    /* Set up NOTIFYICONDATAW. */
    memset (&nid, 0, sizeof (nid));
    nid.cbSize           = sizeof (nid);
    nid.hWnd             = msg_hwnd;
    nid.uID              = 1;
    nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon            = icon;

    if (tooltip_utf8) {
        wchar_t *tip = utf8_to_wchar (tooltip_utf8);
        if (tip) {
            wcsncpy (nid.szTip, tip, G_N_ELEMENTS (nid.szTip) - 1);
            g_free (tip);
        }
    }

    if (!Shell_NotifyIconW (NIM_ADD, &nid)) {
        tray_log ("Shell_NotifyIconW(NIM_ADD) FAILED (error %lu)", GetLastError ());
        DestroyWindow (msg_hwnd);
        msg_hwnd = NULL;
        return FALSE;
    }

    /* Try NOTIFYICON_VERSION_4 (Windows Vista+), fall back to v3. */
    nid.uVersion = NOTIFYICON_VERSION_4;
    if (Shell_NotifyIconW (NIM_SETVERSION, &nid)) {
        using_version_4 = TRUE;
        tray_log ("Using NOTIFYICON_VERSION_4");
        /* V4 requires NIF_SHOWTIP for tooltip to appear. */
        nid.uFlags |= NIF_SHOWTIP;
        Shell_NotifyIconW (NIM_MODIFY, &nid);
    } else {
        nid.uVersion = NOTIFYICON_VERSION;
        Shell_NotifyIconW (NIM_SETVERSION, &nid);
        using_version_4 = FALSE;
        tray_log ("Using NOTIFYICON_VERSION (v3 fallback)");
    }

    initialised = TRUE;
    tray_log ("Tray icon created (hwnd=%p, version=%s)",
              (void *) msg_hwnd, using_version_4 ? "4" : "3");

    /* Create an empty popup menu (will be filled by set_menu). */
    popup_menu = CreatePopupMenu ();

    return TRUE;
}

void
systray_win32_set_menu (const gchar **labels, guint32 checked_mask)
{
    if (popup_menu == NULL) return;

    /* Clear existing items. */
    while (GetMenuItemCount (popup_menu) > 0)
        RemoveMenu (popup_menu, 0, MF_BYPOSITION);

    if (labels == NULL) return;

    for (int i = 0; labels[i] != NULL && i < MAX_MENU_ITEMS; i++) {
        if (labels[i][0] == '\0') {
            AppendMenuW (popup_menu, MF_SEPARATOR, 0, NULL);
        } else {
            wchar_t *w = utf8_to_wchar (labels[i]);
            UINT flags = MF_STRING;
            if (checked_mask & (1u << i))
                flags |= MF_CHECKED;
            AppendMenuW (popup_menu, flags, (UINT_PTR)(i + 1), w);
            g_free (w);
        }
    }
}

void
systray_win32_set_tooltip (const gchar *tooltip_utf8)
{
    if (!initialised) return;

    memset (nid.szTip, 0, sizeof (nid.szTip));
    if (tooltip_utf8) {
        wchar_t *tip = utf8_to_wchar (tooltip_utf8);
        if (tip) {
            wcsncpy (nid.szTip, tip, G_N_ELEMENTS (nid.szTip) - 1);
            g_free (tip);
        }
    }
    nid.uFlags = NIF_TIP;
    Shell_NotifyIconW (NIM_MODIFY, &nid);
}

void
systray_win32_show_balloon (const gchar                  *title_utf8,
                            const gchar                  *body_utf8,
                            int                           icon_type,
                            SystrayWin32BalloonCallback   callback,
                            gpointer                      balloon_user_data)
{
    if (!initialised) return;

    balloon_callback = callback;
    balloon_data_ptr = balloon_user_data;

    nid.uFlags = NIF_INFO;

    /* Title (max 63 chars) */
    memset (nid.szInfoTitle, 0, sizeof (nid.szInfoTitle));
    if (title_utf8) {
        wchar_t *wtitle = utf8_to_wchar (title_utf8);
        if (wtitle) {
            wcsncpy (nid.szInfoTitle, wtitle, G_N_ELEMENTS (nid.szInfoTitle) - 1);
            g_free (wtitle);
        }
    }

    /* Body (max 255 chars) */
    memset (nid.szInfo, 0, sizeof (nid.szInfo));
    if (body_utf8) {
        wchar_t *wbody = utf8_to_wchar (body_utf8);
        if (wbody) {
            wcsncpy (nid.szInfo, wbody, G_N_ELEMENTS (nid.szInfo) - 1);
            g_free (wbody);
        }
    }

    /* Icon type: NIIF_NONE=0, NIIF_INFO=1, NIIF_WARNING=2, NIIF_ERROR=3 */
    nid.dwInfoFlags = (icon_type >= 0 && icon_type <= 3) ? (DWORD) icon_type : NIIF_INFO;

    Shell_NotifyIconW (NIM_MODIFY, &nid);
}

void
systray_win32_hide_balloon (void)
{
    if (!initialised) return;

    balloon_callback = NULL;
    balloon_data_ptr = NULL;

    /* Set szInfo to empty string to dismiss the balloon */
    nid.uFlags = NIF_INFO;
    memset (nid.szInfo, 0, sizeof (nid.szInfo));
    memset (nid.szInfoTitle, 0, sizeof (nid.szInfoTitle));
    Shell_NotifyIconW (NIM_MODIFY, &nid);
}

void
systray_win32_cleanup (void)
{
    if (!initialised) return;
    tray_log ("Cleanup: removing tray icon");
    initialised = FALSE;

    Shell_NotifyIconW (NIM_DELETE, &nid);

    if (popup_menu) {
        DestroyMenu (popup_menu);
        popup_menu = NULL;
    }
    if (msg_hwnd) {
        DestroyWindow (msg_hwnd);
        msg_hwnd = NULL;
    }

    user_callback  = NULL;
    user_data_ptr  = NULL;
    balloon_callback = NULL;
    balloon_data_ptr = NULL;

    if (tray_log_file) {
        fprintf (tray_log_file, "=== Log closed ===\n");
        fclose (tray_log_file);
        tray_log_file = NULL;
    }
}

/* ---- Window procedure ---- */

static void
show_context_menu (HWND hwnd)
{
    if (popup_menu == NULL) return;

    POINT pt = {0, 0};
    GetCursorPos (&pt);
    SetForegroundWindow (hwnd);

    int cmd = (int) TrackPopupMenu (popup_menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        pt.x, pt.y, 0, hwnd, NULL);

    PostMessage (hwnd, WM_NULL, 0, 0);   /* dismiss cleanly */

    tray_log ("Menu command = %d", cmd);
    if (cmd > 0 && user_callback)
        user_callback (cmd - 1, user_data_ptr);
}

static LRESULT CALLBACK
wnd_proc (HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    /* Explorer restarted — re-create our tray icon. */
    if (WM_TASKBARCREATED != 0 && msg == WM_TASKBARCREATED) {
        tray_log ("TaskbarCreated — re-adding tray icon");
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        if (using_version_4)
            nid.uFlags |= NIF_SHOWTIP;
        Shell_NotifyIconW (NIM_ADD, &nid);
        nid.uVersion = using_version_4 ? NOTIFYICON_VERSION_4
                                       : NOTIFYICON_VERSION;
        Shell_NotifyIconW (NIM_SETVERSION, &nid);
        return 0;
    }

    if (msg == WM_TRAYICON) {
        UINT event = LOWORD (lParam);
        tray_log ("WM_TRAYICON event=0x%04x wParam=0x%08lx lParam=0x%08lx",
                  event, (unsigned long) wParam, (unsigned long) lParam);

        switch (event) {

        /* ---- Left-click / keyboard select (V4 primary) ---- */
        case NIN_SELECT:
        case NIN_KEYSELECT:
            tray_log ("Left-click (NIN_SELECT / NIN_KEYSELECT)");
            if (user_callback)
                user_callback (-1, user_data_ptr);
            break;

        case WM_LBUTTONUP:
            /* V3 fallback — V4 sends NIN_SELECT instead. */
            if (!using_version_4) {
                tray_log ("Left-click (WM_LBUTTONUP, v3)");
                if (user_callback)
                    user_callback (-1, user_data_ptr);
            }
            break;

        /* ---- Balloon notifications ---- */
        case NIN_BALLOONUSERCLICK:
            tray_log ("Balloon user click");
            if (balloon_callback) {
                SystrayWin32BalloonCallback cb = balloon_callback;
                gpointer data = balloon_data_ptr;
                balloon_callback = NULL;
                balloon_data_ptr = NULL;
                cb (data);
            }
            break;

        case NIN_BALLOONTIMEOUT:
            tray_log ("Balloon timeout");
            balloon_callback = NULL;
            balloon_data_ptr = NULL;
            break;

        /* ---- Right-click / context menu (V4 primary) ---- */
        case WM_CONTEXTMENU:
            tray_log ("Right-click (WM_CONTEXTMENU)");
            show_context_menu (hwnd);
            break;

        case WM_RBUTTONUP:
            /* V3 fallback — V4 sends WM_CONTEXTMENU instead. */
            if (!using_version_4) {
                tray_log ("Right-click (WM_RBUTTONUP, v3)");
                show_context_menu (hwnd);
            }
            break;

        default:
            break;
        }
        return 0;
    }

    return DefWindowProcW (hwnd, msg, wParam, lParam);
}

#else /* !_WIN32 — stubs for Linux builds (never called) */

gboolean systray_win32_init (const gchar *t, int r, SystrayWin32Callback c, gpointer u) { return FALSE; }
void systray_win32_set_menu (const gchar **l, guint32 m) {}
void systray_win32_set_tooltip (const gchar *t) {}
void systray_win32_show_balloon (const gchar *t, const gchar *b, int i, SystrayWin32BalloonCallback c, gpointer u) {}
void systray_win32_hide_balloon (void) {}
void systray_win32_cleanup (void) {}

#endif
