/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Windows Systray Stub - No tray icon on Windows, window close = quit.
 */
using Gtk;
using GLib;

namespace Dino.Ui {

    public class SystrayManager : Object {
        
        private unowned Application application;
        public MainWindow? window;
        
        public SystrayManager(Application application) {
            this.application = application;
        }
        
        public void set_window(MainWindow window) {
            this.window = window;
            
            // On Windows: closing the window quits the application.
            // No system tray support (StatusNotifierItem is Linux D-Bus only).
            window.close_request.connect(() => {
                quit_application();
                return true;
            });
        }
        
        public void quit_application() {
            application.quit();
        }
        
        public void cleanup() {
            // Nothing to clean up in the Windows stub
        }
    }
}
