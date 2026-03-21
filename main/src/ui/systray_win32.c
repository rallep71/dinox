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
#include <objbase.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>   /* _set_invalid_parameter_handler */

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
#define SYSTRAY_BUILD_ID "2026-03-17-v9"

/* Menu items are plain MF_STRING — Windows 10/11 renders them natively
 * with Segoe UI, ClearType, DPI scaling, and theme-aware colors.
 * Colored status emoji (🟢🟠🔴⭕/⚪) are embedded in the label text
 * by the Vala caller (systray_windows.vala). */

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

static HANDLE          single_instance_mutex = NULL;
static DWORD           last_context_menu_tick = 0;

#define WM_ACTIVATE_INSTANCE  (WM_APP + 2)

/* ---- debug log → %TEMP%/dinox_systray.log ---- */
static void
tray_log (const char *fmt, ...)
{
    va_list ap;
    va_start (ap, fmt);

    if (tray_log_file == NULL) {
        /* Prefer %TEMP% (native Windows path) over g_get_tmp_dir()
         * which returns MSYS2-style /tmp on MinGW builds. */
        const char *tmp = g_getenv ("TEMP");
        if (tmp == NULL || tmp[0] == '\0')
            tmp = g_getenv ("TMP");
        if (tmp == NULL || tmp[0] == '\0')
            tmp = g_get_tmp_dir ();
        char *path = g_build_filename (tmp, "dinox_systray.log", NULL);
        tray_log_file = fopen (path, "w");
        g_free (path);
        if (tray_log_file) {
            fprintf (tray_log_file, "=== DinoX Systray Debug Log ===\n");
            fprintf (tray_log_file, "Build: %s\n\n", SYSTRAY_BUILD_ID);
        }
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

/* ---- suppress taskbar Jump List "launch" entry ---- */
/*
 * Windows shows a "DinoX" launch entry in the taskbar right-click menu by
 * default.  Since left-clicking the taskbar button already toggles the
 * window, the extra entry is redundant and confusing.  Setting an empty
 * custom jump list via ICustomDestinationList removes it while keeping the
 * "Pin to taskbar" and "Close window" entries intact.
 *
 * Additionally, SetCurrentProcessExplicitAppUserModelID is called so
 * that Windows associates the correct App ID with our process — this is
 * required for the jump-list suppression to stick and prevents Windows
 * from auto-generating a launch shortcut based on the executable path.
 */

/* SetCurrentProcessExplicitAppUserModelID (shell32.dll) */
typedef HRESULT (WINAPI *pfn_SetAppUserModelID)(PCWSTR);

/* ICustomDestinationList {6332DEBF-87B5-4670-90C0-5E57B408A49E} */
static const IID IID_ICustomDestinationList = {
    0x6332DEBF, 0x87B5, 0x4670,
    { 0x90, 0xC0, 0x5E, 0x57, 0xB4, 0x08, 0xA4, 0x9E }
};
/* CLSID_DestinationList {77F10CF0-3DB5-4966-B520-B7C54FD35ED6} */
static const CLSID CLSID_DestinationList = {
    0x77F10CF0, 0x3DB5, 0x4966,
    { 0xB5, 0x20, 0xB7, 0xC5, 0x4F, 0xD3, 0x5E, 0xD6 }
};

static void
suppress_jumplist (void)
{
    HRESULT hr;
    void *cdl = NULL;

    /* 1) Set explicit AppUserModelID so Windows associates our process
     *    with a stable ID instead of auto-generating one from the exe path. */
    HMODULE shell32 = GetModuleHandleW (L"shell32.dll");
    if (shell32) {
        pfn_SetAppUserModelID pSetID = (pfn_SetAppUserModelID)
            GetProcAddress (shell32, "SetCurrentProcessExplicitAppUserModelID");
        if (pSetID) {
            hr = pSetID (L"im.github.rallep71.DinoX");
            tray_log ("suppress_jumplist: SetAppUserModelID %s (0x%08lx)",
                      SUCCEEDED (hr) ? "OK" : "FAILED", (unsigned long) hr);
        }
    }

    /* 2) Delete any existing jump list, then commit an empty one. */
    hr = CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
    gboolean did_coinit = SUCCEEDED (hr);

    hr = CoCreateInstance (&CLSID_DestinationList, NULL, CLSCTX_INPROC_SERVER,
                           &IID_ICustomDestinationList, &cdl);
    if (FAILED (hr) || cdl == NULL) {
        tray_log ("suppress_jumplist: CoCreateInstance failed (0x%08lx)", (unsigned long) hr);
        if (did_coinit) CoUninitialize ();
        return;
    }

    /* ICustomDestinationList vtable layout (IUnknown + interface):
     * 0: QueryInterface  1: AddRef  2: Release
     * 3: SetAppID  4: BeginList  5: AppendCategory
     * 6: AppendKnownCategory  7: AddUserTasks  8: CommitList
     * 9: GetRemovedDestinations  10: DeleteList  11: AbortList */

    typedef HRESULT (STDMETHODCALLTYPE *pfn_SetAppID)(void *, LPCWSTR);
    typedef HRESULT (STDMETHODCALLTYPE *pfn_BeginList)(void *, UINT *, const IID *, void **);
    typedef HRESULT (STDMETHODCALLTYPE *pfn_CommitList)(void *);
    typedef HRESULT (STDMETHODCALLTYPE *pfn_DeleteList)(void *, LPCWSTR);
    typedef ULONG   (STDMETHODCALLTYPE *pfn_Release)(void *);

    void **vtbl = *(void ***)cdl;

    /* SetAppID on the destination list object */
    hr = ((pfn_SetAppID)vtbl[3])(cdl, L"im.github.rallep71.DinoX");
    tray_log ("suppress_jumplist: CDL.SetAppID %s (0x%08lx)",
              SUCCEEDED (hr) ? "OK" : "FAILED", (unsigned long) hr);

    /* DeleteList — removes the entire custom jump list for our AppID. */
    hr = ((pfn_DeleteList)vtbl[10])(cdl, L"im.github.rallep71.DinoX");
    tray_log ("suppress_jumplist: DeleteList %s (0x%08lx)",
              SUCCEEDED (hr) ? "OK" : "FAILED", (unsigned long) hr);

    /* Also do BeginList + CommitList with zero entries (belt and suspenders). */
    UINT min_slots = 0;
    void *removed = NULL;
    /* IID_IObjectArray {92CA9DCD-5622-4BBA-A805-5E9F541BD8C9} */
    static const IID IID_IObjectArray = {
        0x92CA9DCD, 0x5622, 0x4BBA,
        { 0xA8, 0x05, 0x5E, 0x9F, 0x54, 0x1B, 0xD8, 0xC9 }
    };

    hr = ((pfn_BeginList)vtbl[4])(cdl, &min_slots, &IID_IObjectArray, &removed);
    if (SUCCEEDED (hr)) {
        hr = ((pfn_CommitList)vtbl[8])(cdl);
        tray_log ("suppress_jumplist: CommitList %s (0x%08lx)",
                  SUCCEEDED (hr) ? "OK" : "FAILED", (unsigned long) hr);
        /* Release the removed-destinations array */
        if (removed) {
            void **rv = *(void ***)removed;
            ((pfn_Release)rv[2])(removed);
        }
    } else {
        tray_log ("suppress_jumplist: BeginList failed (0x%08lx)", (unsigned long) hr);
    }

    ((pfn_Release)vtbl[2])(cdl);
    if (did_coinit) CoUninitialize ();
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
systray_win32_check_single_instance (void)
{
    single_instance_mutex = CreateMutexW (NULL, FALSE,
                                          L"DinoX_SingleInstance_Mutex");
    if (GetLastError () == ERROR_ALREADY_EXISTS) {
        /* Another instance is already running.
         * Find its tray callback window and tell it to show itself. */
        HWND existing = FindWindowW (L"DinoXSystrayMsg", NULL);
        if (existing != NULL) {
            PostMessageW (existing, WM_ACTIVATE_INSTANCE, 0, 0);
            tray_log ("Another instance found (hwnd=%p), sent activate",
                      (void *) existing);
        }
        if (single_instance_mutex) {
            CloseHandle (single_instance_mutex);
            single_instance_mutex = NULL;
        }
        return FALSE;   /* caller should exit */
    }
    tray_log ("Single-instance mutex acquired — we are the primary");
    return TRUE;   /* we are the primary instance */
}

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
    tray_log ("=== Tray icon created ===");
    tray_log ("  hwnd       = %p", (void *) msg_hwnd);
    tray_log ("  version    = %s", using_version_4 ? "V4" : "V3");
    tray_log ("  build      = %s", SYSTRAY_BUILD_ID);
    tray_log ("  WM_CLOSE   = protected (return 0)");
    tray_log ("  RBUTTONUP  = handled in ALL modes");
    tray_log ("  mutex      = %p", (void *) single_instance_mutex);
    tray_log ("========================");

    /* Remove the "DinoX" launch entry from the taskbar right-click menu.
     * Left-click already toggles the window, so the extra item is redundant. */
    suppress_jumplist ();

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
            /* Plain MF_STRING: Windows renders natively with Segoe UI,
             * ClearType, DPI awareness, and dark-mode support.
             * Emoji in the label provide colored status circles. */
            wchar_t *w = utf8_to_wchar (labels[i]);
            AppendMenuW (popup_menu, MF_STRING, (UINT_PTR)(i + 1), w);
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
    if (single_instance_mutex) {
        ReleaseMutex (single_instance_mutex);
        CloseHandle (single_instance_mutex);
        single_instance_mutex = NULL;
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
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
        pt.x, pt.y, 0, hwnd, NULL);

    PostMessage (hwnd, WM_NULL, 0, 0);   /* dismiss cleanly */

    tray_log ("Menu command = %d", cmd);
    if (cmd > 0 && user_callback)
        user_callback (cmd - 1, user_data_ptr);
}

static LRESULT CALLBACK
wnd_proc (HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    /* Owner-drawn menu code removed — using native MF_STRING items now.
     * Windows renders them with Segoe UI, ClearType, and theme colors. */

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

    /* Don't let Windows destroy our tray callback window.
     * The shell's "Fenster schliessen" or system shutdown may send
     * WM_CLOSE to all top-level windows of the process. */
    if (msg == WM_CLOSE) {
        tray_log ("WM_CLOSE received on msg_hwnd — ignoring (tray stays alive)");
        return 0;
    }

    /* Windows is shutting down / user is logging off.
     * Tell our Vala-side to quit gracefully (menu_id = -3). */
    if (msg == WM_QUERYENDSESSION) {
        tray_log ("WM_QUERYENDSESSION — allowing shutdown");
        return TRUE;  /* "yes, we can quit" */
    }
    if (msg == WM_ENDSESSION && wParam) {
        tray_log ("WM_ENDSESSION — graceful shutdown");
        if (user_callback)
            user_callback (-3, user_data_ptr);   /* -3 = system shutdown */
        return 0;
    }

    /* Second instance asked us to show the window (single-instance). */
    if (msg == WM_ACTIVATE_INSTANCE) {
        tray_log ("WM_ACTIVATE_INSTANCE — showing window from second instance");
        if (user_callback)
            user_callback (-2, user_data_ptr);   /* -2 = always show */
        return 0;
    }

    if (msg == WM_TRAYICON) {
        UINT event = LOWORD (lParam);

        /* Only log meaningful events, skip WM_MOUSEMOVE (0x0200) spam */
        if (event != WM_MOUSEMOVE) {
            tray_log ("WM_TRAYICON event=0x%04x wParam=0x%08lx lParam=0x%08lx",
                      event, (unsigned long) wParam, (unsigned long) lParam);
        }

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

        /* ---- Right-click / context menu ---- */
        case WM_CONTEXTMENU:
            tray_log ("Right-click (WM_CONTEXTMENU)");
            {
                DWORD now = GetTickCount ();
                if (now - last_context_menu_tick > 400) {
                    last_context_menu_tick = now;
                    show_context_menu (hwnd);
                }
            }
            break;

        case WM_RBUTTONUP:
            /* Handle in ALL modes — Windows 10/11 may send WM_RBUTTONUP
             * even in V4, or fail to deliver WM_CONTEXTMENU entirely
             * (shell intercepts right-click for its own menu). */
            tray_log ("Right-click (WM_RBUTTONUP)");
            {
                DWORD now = GetTickCount ();
                if (now - last_context_menu_tick > 400) {
                    last_context_menu_tick = now;
                    show_context_menu (hwnd);
                }
            }
            break;

        default:
            break;
        }
        return 0;
    }

    return DefWindowProcW (hwnd, msg, wParam, lParam);
}

/* ---- Attach to parent console (for CMD/MSYS2 log output) ---- */
/*
 * With -mwindows the EXE is GUI subsystem → no console on double-click.
 * But when launched from CMD or MSYS2, we want stdout/stderr to go to
 * that terminal.  AttachConsole(ATTACH_PARENT_PROCESS) connects us to
 * the parent's console; then we reopen the C stdio streams to CONOUT$.
 *
 * When there IS no parent console (Explorer double-click), we allocate
 * a hidden console.  This is critical: without a console, every child
 * process that is itself a console application (gpg.exe, gpg-agent.exe,
 * openssl.exe, etc.) will cause Windows to create a NEW visible console
 * window — producing the "flashing CMD" effect.  With a hidden console
 * attached to our process, all children (and grandchildren) inherit it
 * transparently, and no visible windows appear.
 */
void
systray_win32_attach_parent_console (void)
{
    /* DINOX_LOG_FILE: if set, redirect stderr (GLib debug messages)
     * to the specified file instead of CONOUT$/NUL.  Usage:
     *   DINOX_LOG_FILE=dinox-debug.log ./dinox.exe            */
    const char *log_file = g_getenv ("DINOX_LOG_FILE");

    if (AttachConsole (ATTACH_PARENT_PROCESS)) {
        freopen ("CONOUT$", "w", stdout);
        if (log_file && *log_file)
            freopen (log_file, "w", stderr);
        else
            freopen ("CONOUT$", "w", stderr);
        /* Also fix up stdin so interactive input works if needed. */
        freopen ("CONIN$",  "r", stdin);
        tray_log ("AttachConsole(PARENT) succeeded — attached to parent console");
    } else {
        /* No parent console (Explorer / desktop shortcut launch).
         * Allocate our own console and immediately hide it so that
         * child processes inherit a console handle instead of Windows
         * creating a new visible CMD window for each one. */
        AllocConsole ();
        HWND console_hwnd = GetConsoleWindow ();
        if (console_hwnd)
            ShowWindow (console_hwnd, SW_HIDE);

        /* Redirect C stdio to NUL — there is no terminal to write to. */
        freopen ("NUL", "w", stdout);
        if (log_file && *log_file)
            freopen (log_file, "w", stderr);
        else
            freopen ("NUL", "w", stderr);
        freopen ("NUL", "r", stdin);
        tray_log ("Allocated hidden console for child-process inheritance");
    }

    /* Auto-enable GLib debug output ONLY when DINOX_LOG_FILE is explicitly
     * set.  Normal shell usage (CMD, PowerShell, MSYS2) stays quiet. */
    if (log_file && *log_file && !g_getenv ("G_MESSAGES_DEBUG"))
        g_setenv ("G_MESSAGES_DEBUG", "all", FALSE);
}

/* ---- Set process-level AppUserModelID ---- */
/*
 * Must be called BEFORE any windows are created (so before Gtk.init()).
 * This tells Windows which app identity to use for taskbar grouping and
 * jump list operations.  Without it, Windows generates one from the exe
 * path and our suppress_jumplist() may not target the right ID.
 */
void
systray_win32_set_app_id (const gchar *app_id_utf8)
{
    if (app_id_utf8 == NULL) return;
    HMODULE shell32 = GetModuleHandleW (L"shell32.dll");
    if (!shell32) shell32 = LoadLibraryW (L"shell32.dll");
    if (shell32) {
        pfn_SetAppUserModelID pSetID = (pfn_SetAppUserModelID)
            GetProcAddress (shell32, "SetCurrentProcessExplicitAppUserModelID");
        if (pSetID) {
            wchar_t *wid = utf8_to_wchar (app_id_utf8);
            HRESULT hr = pSetID (wid);
            tray_log ("SetAppUserModelID('%s') %s (0x%08lx)",
                      app_id_utf8,
                      SUCCEEDED (hr) ? "OK" : "FAILED",
                      (unsigned long) hr);
            g_free (wid);
        }
    }
}

/* ---- Suppress CRT invalid-parameter assertions ---- */
/*
 * GStreamer's MediaFoundation plugin spawns worker threads that probe
 * hardware encoders/decoders.  When a device is not available, the MF API
 * sometimes calls CRT functions with invalid parameters.
 *
 * On MinGW64 (MSVCRT runtime), _set_invalid_parameter_handler is process-
 * wide (not thread-local like on UCRT/MSVC).  GLib's g_win32_push/pop_
 * invalid_parameter_handler therefore has a TOCTOU race: if any thread
 * (e.g. MediaFoundation worker) calls _set_invalid_parameter_handler
 * between GLib's push and pop, the pop assertion fires:
 *
 *   GLib-CRITICAL (recursed) **: g_win32_pop_invalid_parameter_handler:
 *   assertion 'handler->pushed_handler == popped_handler' failed
 *
 * The "(recursed)" means the g_critical fires while another g_log is
 * already active on the same thread.  GLib's hardcoded fallback handler
 * for recursive messages calls MessageBoxW() directly — no GLib API
 * (g_log_set_handler, g_log_set_writer_func, etc.) can intercept this.
 *
 * The fix has two layers:
 *   1. _set_invalid_parameter_handler → silent handler (reduces frequency)
 *   2. IAT-patch MessageBoxW in libglib-2.0-0.dll to suppress exactly
 *      this one dialog while letting all other message boxes through.
 */
static void
silent_invalid_parameter_handler (
    const wchar_t *expression,
    const wchar_t *function,
    const wchar_t *file,
    unsigned int   line,
    uintptr_t      reserved)
{
    /* intentionally empty — suppress the CRT assertion dialog */
}

/* --- IAT patching to suppress GLib's recursive CRT handler dialog --- */

typedef int (WINAPI *MessageBoxW_fn)(HWND, LPCWSTR, LPCWSTR, UINT);
static MessageBoxW_fn Real_MessageBoxW = NULL;

static int WINAPI
filtered_message_box_w (HWND hWnd, LPCWSTR lpText,
                        LPCWSTR lpCaption, UINT uType)
{
    /* Suppress only the GLib CRT handler mismatch dialog */
    if (lpText && wcsstr (lpText, L"pop_invalid_parameter_handler"))
    {
        tray_log ("Suppressed GLib CRT handler assertion dialog");
        return IDOK;
    }
    return Real_MessageBoxW (hWnd, lpText, lpCaption, uType);
}

/*
 * Walk the Import Address Table (IAT) of the given module and replace
 * the entry for MessageBoxW (from user32.dll) with our filtered version.
 */
static void
patch_module_iat_messagebox (HMODULE module)
{
    if (!module) return;

    BYTE *base = (BYTE *) module;
    PIMAGE_DOS_HEADER dos = (PIMAGE_DOS_HEADER) base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;

    PIMAGE_NT_HEADERS nt = (PIMAGE_NT_HEADERS) (base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return;

    DWORD import_rva =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if (!import_rva) return;

    PIMAGE_IMPORT_DESCRIPTOR imp = (PIMAGE_IMPORT_DESCRIPTOR) (base + import_rva);

    for (; imp->Name; imp++)
    {
        const char *dll = (const char *) (base + imp->Name);
        if (_stricmp (dll, "user32.dll") != 0)
            continue;

        PIMAGE_THUNK_DATA orig  = (PIMAGE_THUNK_DATA) (base + imp->OriginalFirstThunk);
        PIMAGE_THUNK_DATA thunk = (PIMAGE_THUNK_DATA) (base + imp->FirstThunk);

        for (; orig->u1.AddressOfData; orig++, thunk++)
        {
            if (IMAGE_SNAP_BY_ORDINAL (orig->u1.Ordinal))
                continue;

            PIMAGE_IMPORT_BY_NAME name =
                (PIMAGE_IMPORT_BY_NAME) (base + orig->u1.AddressOfData);

            if (strcmp ((const char *) name->Name, "MessageBoxW") == 0)
            {
                Real_MessageBoxW = (MessageBoxW_fn) thunk->u1.Function;

                DWORD old_protect;
                if (VirtualProtect (&thunk->u1.Function, sizeof (FARPROC),
                                    PAGE_READWRITE, &old_protect))
                {
                    thunk->u1.Function = (ULONG_PTR) filtered_message_box_w;
                    VirtualProtect (&thunk->u1.Function, sizeof (FARPROC),
                                    old_protect, &old_protect);
                    tray_log ("Patched MessageBoxW in GLib IAT");
                }
                return;
            }
        }
    }
    tray_log ("WARNING: MessageBoxW not found in module IAT");
}

void
systray_win32_suppress_crt_assertions (void)
{
    /* Layer 1: silent CRT handler (reduces trigger frequency) */
    _set_invalid_parameter_handler (silent_invalid_parameter_handler);

    /* Layer 2: patch GLib's MessageBoxW import to suppress the recursive
     * assertion dialog that no GLib API can intercept */
    Real_MessageBoxW = (MessageBoxW_fn) GetProcAddress (
        GetModuleHandleW (L"user32.dll"), "MessageBoxW");

    HMODULE glib = GetModuleHandleW (L"libglib-2.0-0.dll");
    if (glib)
        patch_module_iat_messagebox (glib);
    else
        tray_log ("WARNING: libglib-2.0-0.dll not loaded yet");

    tray_log ("CRT invalid-parameter handler suppressed");
}

#else /* !_WIN32 — stubs for Linux builds (never called) */

gboolean systray_win32_check_single_instance (void) { return TRUE; }
gboolean systray_win32_init (const gchar *t, int r, SystrayWin32Callback c, gpointer u) { return FALSE; }
void systray_win32_set_menu (const gchar **l, guint32 m) {}
void systray_win32_set_tooltip (const gchar *t) {}
void systray_win32_show_balloon (const gchar *t, const gchar *b, int i, SystrayWin32BalloonCallback c, gpointer u) {}
void systray_win32_hide_balloon (void) {}
void systray_win32_cleanup (void) {}
void systray_win32_attach_parent_console (void) {}
void systray_win32_set_app_id (const gchar *app_id_utf8) {}
void systray_win32_suppress_crt_assertions (void) {}

#endif
