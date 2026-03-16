/*
 * Copyright (C) 2025-2026 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Windows Systray — Shell_NotifyIcon via systray_win32.c helper.
 * Provides tray icon with left-click toggle and right-click context menu
 * (status selection + Quit).
 *
 * Mirrors the Linux SystrayManager (systray.vala) behaviour:
 *   - Left-click → toggle window show/hide
 *   - Right-click → context menu: Online / Away / Busy / Not Available / ─ / Quit
 *   - Window X → hide to tray (no balloon), app stays alive
 *   - "Quit" menu item → graceful disconnect + exit
 */
using Gtk;
using GLib;

namespace Dino.Ui {

    public class SystrayManager : Object {

        private unowned Application application;
        public MainWindow? window;
        public bool is_hidden = false;
        private bool disposed = false;
        private bool holding = false;
        private bool tray_available = false;

        /* Menu layout:  Online(0) Away(1) Busy(2) N/A(3) sep(4) Quit(5) */
        private const int MENU_QUIT_ID = 5;
        private string[] status_keys = {"online", "away", "dnd", "xa"};
        private string current_status = "online";

        public SystrayManager(Application application) {
            this.application = application;

            bool ok = SystrayWin32.init("DinoX", 1, on_tray_callback, (void*) this);
            if (!ok) {
                warning("Systray: Shell_NotifyIcon init failed — running without tray");
                return;
            }

            tray_available = true;
            // On Windows there is no D-Bus session to keep the main loop alive.
            // hold() once so GApplication doesn't quit when the window is hidden.
            // (Matches the Linux hold_app() fallback for missing SNI watcher.)
            application.hold();
            holding = true;
            rebuild_menu();
            debug("Systray: Win32 tray icon created");
        }

        public void set_window(MainWindow window) {
            this.window = window;

            window.close_request.connect(() => {
                if (Dino.Application.get_default().settings.keep_background && tray_available) {
                    // Just hide — matches Linux behaviour (no balloon, no hold)
                    hide_window();
                    return true;
                } else {
                    quit_application();
                    return true;
                }
            });

            /* Track status changes for menu checkmarks */
            var pm = application.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            pm.status_changed.connect((show, msg) => {
                current_status = show;
                rebuild_menu();
            });
            current_status = pm.get_current_show();
            rebuild_menu();
        }

        /* ---- menu ---- */

        private void rebuild_menu() {
            string[] status_labels = {_("Online"), _("Away"), _("Busy"), _("Not Available")};
            string[] active_emojis = {"\xf0\x9f\x9f\xa2", "\xf0\x9f\x9f\xa0", "\xf0\x9f\x94\xb4", "\xe2\xad\x95"};
            string inactive = "\xe2\x9a\xaa";

            /* Build NULL-terminated label array.  Empty string = separator. */
            string?[] labels = new string?[7];
            uint32 checked = 0;
            for (int i = 0; i < 4; i++) {
                string emoji = (status_keys[i] == current_status) ? active_emojis[i] : inactive;
                labels[i] = emoji + "  " + status_labels[i];
                if (status_keys[i] == current_status)
                    checked |= (1u << i);
            }
            labels[4] = "";     /* separator (empty string) */
            labels[5] = _("Quit");
            /* labels[6] stays null → array terminator */

            SystrayWin32.set_menu(labels, checked);
        }

        /* ---- callbacks ---- */

        private static void on_tray_callback(int menu_id, void* user_data) {
            unowned SystrayManager self = (SystrayManager) user_data;
            if (self.disposed) return;

            if (menu_id == -1) {
                /* Left-click: toggle window */
                self.toggle_window_visibility();
            } else if (menu_id == -2) {
                /* Second instance activation: always show window */
                self.show_window();
            } else if (menu_id == -3) {
                /* System shutdown/logoff — graceful quit */
                Idle.add(() => {
                    self.quit_application();
                    return Source.REMOVE;
                });
            } else if (menu_id == MENU_QUIT_ID) {
                /* Quit — use Idle to escape the Win32 message handler stack */
                Idle.add(() => {
                    self.quit_application();
                    return Source.REMOVE;
                });
            } else if (menu_id >= 0 && menu_id < 4) {
                /* Status change */
                string status = self.status_keys[menu_id];
                self.application.activate_action("set-status", new Variant.string(status));
            }
        }

        /* ---- window visibility ---- */

        public void toggle_window_visibility() {
            if (window == null) return;
            if (is_hidden || !window.is_visible()) {
                show_window();
            } else {
                hide_window();
            }
        }

        private void show_window() {
            if (window == null) return;
            debug("Systray: show_window()");
            window.set_visible(true);
            window.present();
            is_hidden = false;
        }

        private void hide_window() {
            if (window == null) return;
            debug("Systray: hide_window()");
            window.set_visible(false);
            is_hidden = true;
        }

        /* ---- quit ---- */

        public void quit_application() {
            debug("Systray: quit_application() called");

            if (window != null)
                window.hide();

            cleanup();

            debug("Systray: Disconnecting all accounts...");
            application.stream_interactor.connection_manager.disconnect_all();

            debug("Systray: Calling application.quit()");
            application.quit();

            debug("Systray: Force exit");
            Process.exit(0);
        }

        /* ---- cleanup ---- */

        public void cleanup() {
            if (disposed) return;
            disposed = true;

            SystrayWin32.cleanup();

            if (holding) {
                application.release();
                holding = false;
            }
        }

        ~SystrayManager() {
            cleanup();
        }
    }
}
