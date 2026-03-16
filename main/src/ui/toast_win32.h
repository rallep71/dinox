/*
 * toast_win32.h — WinRT Toast Notification API for DinoX
 *
 * Uses Shell_NotifyIcon balloon tips as the proven baseline, with
 * WinRT Toast Notifications (Windows 10+) where available.
 * Toast provides action buttons (Accept/Reject for calls) and
 * richer notification UI.
 */

#ifndef TOAST_WIN32_H
#define TOAST_WIN32_H

#include <glib.h>

#ifdef _WIN32

/*
 * Callback when user clicks a toast notification body or action button.
 * action_args: colon-separated string, e.g.:
 *   "open-conversation:123"
 *   "accept-call:123:456"  (conv_id:call_id)
 *   "reject-call:123:456"
 *   "preferences-account:1"
 *   "open-muc-join:123"
 *
 * Called on the GTK main thread (dispatched via g_idle_add).
 */
typedef void (*ToastWin32ActivatedCallback)(const gchar *action_args,
                                            gpointer     user_data);

/*
 * Initialize the WinRT toast notification system.
 * Returns TRUE if toast notifications are available (Windows 10+).
 * On failure (Windows 7/8, missing COM support), returns FALSE.
 * Caller should fall back to balloon tips.
 *
 * app_name: display name shown in notification settings
 * aumid:    Application User Model ID (e.g. "im.github.rallep71.DinoX")
 * callback: called when user interacts with a toast
 * user_data: passed to callback
 */
gboolean toast_win32_init(const gchar                  *app_name,
                           const gchar                  *aumid,
                           ToastWin32ActivatedCallback   callback,
                           gpointer                      user_data);

/*
 * Show a toast notification.
 * xml_utf8: complete toast XML template in UTF-8.
 *           Caller must XML-escape all user content.
 * tag:      unique tag for later retraction (max 64 chars), or NULL.
 */
void toast_win32_show(const gchar *xml_utf8, const gchar *tag);

/*
 * Hide/retract a toast notification by its tag.
 */
void toast_win32_hide(const gchar *tag);

/*
 * Cleanup toast notification system. Call on app shutdown.
 */
void toast_win32_cleanup(void);

#else

/* Linux stubs — toast_win32.c is only compiled on Windows */
typedef void (*ToastWin32ActivatedCallback)(const char *, void *);
static inline gboolean toast_win32_init(const char *n, const char *a,
                                         ToastWin32ActivatedCallback cb,
                                         void *ud) {
    (void)n; (void)a; (void)cb; (void)ud; return FALSE;
}
static inline void toast_win32_show(const char *x, const char *t) { (void)x; (void)t; }
static inline void toast_win32_hide(const char *t) { (void)t; }
static inline void toast_win32_cleanup(void) {}

#endif
#endif /* TOAST_WIN32_H */
