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
#define SYSTRAY_BUILD_ID "2026-03-17-v8"

/* ---- owner-drawn menu item colors ---- */
/* Stored per menu item: color + label for drawing */
typedef struct {
    COLORREF circle_color;      /* fill color for status circle */
    gboolean draw_circle;       /* TRUE = draw colored circle, FALSE = text only */
    gboolean is_active;         /* TRUE = this is the currently selected status */
    wchar_t  label[128];
} MenuItemData;

static MenuItemData menu_items[MAX_MENU_ITEMS];
static int          menu_item_count = 0;

/* Status colors: green, orange, red, grey */
static COLORREF status_colors[4] = {
    RGB (0x22, 0xC5, 0x5E),   /* Online  = green  */
    RGB (0xFF, 0xA5, 0x00),   /* Away    = orange */
    RGB (0xE0, 0x40, 0x40),   /* Busy    = red    */
    RGB (0x99, 0x99, 0x99),   /* N/A     = grey   */
};

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

    menu_item_count = 0;

    for (int i = 0; labels[i] != NULL && i < MAX_MENU_ITEMS; i++) {
        if (labels[i][0] == '\0') {
            AppendMenuW (popup_menu, MF_SEPARATOR, 0, NULL);
        } else if (i < 4) {
            /* Status items (0-3): owner-drawn with colored circle.
             * Strip any leading emoji from the label — we draw the circle ourselves. */
            const gchar *text = labels[i];
            /* Skip leading UTF-8 emoji + whitespace (emoji can be 3-4 bytes) */
            while (*text && ((unsigned char)*text >= 0x80 || *text == ' '))
                text++;
            /* If stripping removed everything, use original */
            if (*text == '\0') text = labels[i];

            MenuItemData *mid = &menu_items[i];
            mid->circle_color = status_colors[i];
            mid->draw_circle  = TRUE;
            mid->is_active    = (checked_mask & (1u << i)) != 0;
            memset (mid->label, 0, sizeof (mid->label));
            wchar_t *w = utf8_to_wchar (text);
            if (w) {
                wcsncpy (mid->label, w, 127);
                g_free (w);
            }

            AppendMenuW (popup_menu, MF_OWNERDRAW,
                         (UINT_PTR)(i + 1), (LPCWSTR)(uintptr_t) i);
            menu_item_count = i + 1;
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
    /* ---- Owner-drawn menu: measure item ---- */
    if (msg == WM_MEASUREITEM) {
        MEASUREITEMSTRUCT *mis = (MEASUREITEMSTRUCT *) lParam;
        if (mis->CtlType == ODT_MENU) {
            int idx = (int)(uintptr_t) mis->itemData;
            if (idx >= 0 && idx < menu_item_count) {
                /* Measure text with the menu font */
                HDC hdc = GetDC (hwnd);
                HFONT menu_font = (HFONT) GetStockObject (DEFAULT_GUI_FONT);
                HFONT old_font = (HFONT) SelectObject (hdc, menu_font);
                SIZE sz;
                GetTextExtentPoint32W (hdc, menu_items[idx].label,
                                       (int) wcslen (menu_items[idx].label), &sz);
                SelectObject (hdc, old_font);
                ReleaseDC (hwnd, hdc);
                /* circle(10) + gap(6) + text + padding */
                mis->itemWidth  = 10 + 6 + sz.cx + 8;
                mis->itemHeight = (sz.cy > 20) ? sz.cy + 4 : 20;
            }
            return TRUE;
        }
    }

    /* ---- Owner-drawn menu: draw item ---- */
    if (msg == WM_DRAWITEM) {
        DRAWITEMSTRUCT *dis = (DRAWITEMSTRUCT *) lParam;
        if (dis->CtlType == ODT_MENU) {
            int idx = (int)(uintptr_t) dis->itemData;
            if (idx >= 0 && idx < menu_item_count) {
                MenuItemData *mid = &menu_items[idx];

                /* Background */
                BOOL selected = (dis->itemState & ODS_SELECTED) != 0;
                COLORREF bg = selected ? GetSysColor (COLOR_HIGHLIGHT)
                                       : GetSysColor (COLOR_MENU);
                COLORREF fg = selected ? GetSysColor (COLOR_HIGHLIGHTTEXT)
                                       : GetSysColor (COLOR_MENUTEXT);
                HBRUSH bg_brush = CreateSolidBrush (bg);
                FillRect (dis->hDC, &dis->rcItem, bg_brush);
                DeleteObject (bg_brush);

                int y_center = (dis->rcItem.top + dis->rcItem.bottom) / 2;
                int x = dis->rcItem.left + 6;

                /* Draw colored circle (filled) */
                if (mid->draw_circle) {
                    int r = 5;  /* radius */
                    HBRUSH circle_brush = CreateSolidBrush (mid->circle_color);
                    HPEN circle_pen = CreatePen (PS_SOLID, 1, mid->circle_color);
                    HBRUSH old_br = (HBRUSH) SelectObject (dis->hDC, circle_brush);
                    HPEN old_pn = (HPEN) SelectObject (dis->hDC, circle_pen);
                    Ellipse (dis->hDC, x - r, y_center - r, x + r, y_center + r);
                    SelectObject (dis->hDC, old_br);
                    SelectObject (dis->hDC, old_pn);
                    DeleteObject (circle_brush);
                    DeleteObject (circle_pen);

                    /* Bold outline for active status */
                    if (mid->is_active) {
                        HPEN bold_pen = CreatePen (PS_SOLID, 2,
                                                    selected ? fg : RGB(0,0,0));
                        HBRUSH hollow = (HBRUSH) GetStockObject (HOLLOW_BRUSH);
                        SelectObject (dis->hDC, bold_pen);
                        SelectObject (dis->hDC, hollow);
                        Ellipse (dis->hDC, x - r - 1, y_center - r - 1,
                                             x + r + 1, y_center + r + 1);
                        DeleteObject (bold_pen);
                    }
                    x += r + 6;
                }

                /* Draw text */
                HFONT menu_font = (HFONT) GetStockObject (DEFAULT_GUI_FONT);
                HFONT old_font = (HFONT) SelectObject (dis->hDC, menu_font);
                SetBkMode (dis->hDC, TRANSPARENT);
                SetTextColor (dis->hDC, fg);
                RECT text_rect = dis->rcItem;
                text_rect.left = x;
                DrawTextW (dis->hDC, mid->label, -1, &text_rect,
                           DT_SINGLELINE | DT_VCENTER | DT_LEFT);
                SelectObject (dis->hDC, old_font);
            }
            return TRUE;
        }
    }

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
 */
void
systray_win32_attach_parent_console (void)
{
    if (AttachConsole (ATTACH_PARENT_PROCESS)) {
        freopen ("CONOUT$", "w", stdout);
        freopen ("CONOUT$", "w", stderr);
        /* Also fix up stdin so interactive input works if needed. */
        freopen ("CONIN$",  "r", stdin);
        tray_log ("AttachConsole(PARENT) succeeded — attached to parent console");
    } else {
        /* Expected when double-clicked from Explorer (no parent console). */
        tray_log ("AttachConsole(PARENT) returned FALSE (error %lu) — no parent console",
                  GetLastError ());
    }
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

#endif
