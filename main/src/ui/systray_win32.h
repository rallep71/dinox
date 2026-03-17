/*
 * Win32 Shell_NotifyIcon systray helper for DinoX.
 * Provides a notification-area icon with left-click toggle and right-click popup menu.
 */

#ifndef SYSTRAY_WIN32_H
#define SYSTRAY_WIN32_H

#include <glib.h>

/* Callback: user clicked a menu item (menu_id = 0..N-1 items, or -1 for left-click,
 * -2 for "always show window" from second instance activation) */
typedef void (*SystrayWin32Callback)(int menu_id, gpointer user_data);

/* Callback: user clicked a balloon notification */
typedef void (*SystrayWin32BalloonCallback)(gpointer user_data);

/* Check if another DinoX instance is already running (named mutex).
 * If yes, activates the existing instance and returns FALSE (caller should exit).
 * If no, acquires the mutex and returns TRUE (caller is the primary instance). */
gboolean systray_win32_check_single_instance (void);

/* Initialise the tray icon.  tooltip_utf8 is shown on hover.
 * icon_resource_id: resource index in the .exe (1 = IDI_ICON1 from dinox.rc)
 * Returns TRUE on success. */
gboolean systray_win32_init   (const gchar          *tooltip_utf8,
                                int                   icon_resource_id,
                                SystrayWin32Callback  callback,
                                gpointer              user_data);

/* Replace the entire popup menu.  labels is a NULL-terminated array of
 * UTF-8 strings.  An empty string ("") inserts a separator.
 * checked_mask: bitmask of items that should show a checkmark (bullet). */
void     systray_win32_set_menu (const gchar **labels, guint32 checked_mask);

/* Update the hover tooltip. */
void     systray_win32_set_tooltip (const gchar *tooltip_utf8);

/* Show a balloon notification (title + body).
 * icon_type: 0 = none, 1 = info, 2 = warning, 3 = error.
 * If callback is non-NULL, it will be called when the user clicks the balloon. */
void     systray_win32_show_balloon (const gchar                  *title_utf8,
                                     const gchar                  *body_utf8,
                                     int                           icon_type,
                                     SystrayWin32BalloonCallback   callback,
                                     gpointer                      balloon_user_data);

/* Hide any currently showing balloon. */
void     systray_win32_hide_balloon (void);

/* Remove tray icon and clean up. */
void     systray_win32_cleanup (void);

/* Attach to parent console (if launched from CMD/MSYS2).
 * With -mwindows the EXE has no console by default; this re-attaches
 * stdout/stderr to an existing parent console so log output is visible
 * when the user runs dinox.exe from a terminal.  No-op when double-clicked
 * from Explorer (no parent console exists). */
void     systray_win32_attach_parent_console (void);

/* Set the process-level AppUserModelID (must be called BEFORE any windows
 * are created).  This controls how Windows groups the app in the taskbar
 * and is required for jump list suppression to work correctly. */
void     systray_win32_set_app_id (const gchar *app_id_utf8);

#endif /* SYSTRAY_WIN32_H */
