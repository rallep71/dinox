/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
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
            
            // WICHTIG für Windows ohne Tray-Icon:
            // Wenn das Fenster geschlossen wird, müssen wir die App beenden.
            // Sonst läuft sie im Hintergrund weiter (wegen hide_on_close=true in application.vala).
            window.close_request.connect(() => {
                quit_application();
                return true;
            });
        }
        
        public void quit_application() {
            // Beende die Anwendung sauber
            application.quit();
        }
        
        public void cleanup() {
            // Nichts zu tun im Dummy
        }
    }
}
