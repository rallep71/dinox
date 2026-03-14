using Dino.Entities;
using Dino.Ui;
using Gst;

extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

#if HAVE_MALLOC_TRIM
[CCode (cname = "mallopt", cheader_filename = "malloc.h")]
extern int mallopt (int param, int value);
#endif

namespace Dino {

void main(string[] args) {

#if HAVE_MALLOC_TRIM
    // Force allocations > 64 KB to use mmap instead of sbrk.  When freed,
    // mmap'd pages are returned to the OS immediately (munmap) instead of
    // lingering in glibc's arena — preventing the heap fragmentation that
    // makes malloc_trim() ineffective for large GStreamer buffer pools.
    mallopt(-3 /* M_MMAP_THRESHOLD */, 65536);
#endif

    // Handle `--version` early (before GTK/GApplication startup).
    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--version") {
            stdout.printf("Dino %s\n", Dino.get_version());
            return;
        }
    }

    try{
        string? exec_path = args.length > 0 ? args[0] : null;
        SearchPathGenerator search_path_generator = new SearchPathGenerator(exec_path);

        // Apply user language override before gettext init
        string lang_file = Path.build_filename(Environment.get_user_data_dir(), "dinox", "language");
        if (FileUtils.test(lang_file, FileTest.EXISTS)) {
            try {
                string lang_code;
                FileUtils.get_contents(lang_file, out lang_code);
                lang_code = lang_code.strip();
                if (lang_code != "" && lang_code != "system") {
                    Environment.set_variable("LANGUAGE", lang_code, true);
                    Environment.set_variable("LANG", lang_code + ".UTF-8", true);
                    Intl.setlocale(LocaleCategory.ALL, "");
                }
            } catch (FileError e) {
                // ignore — use system locale
            }
        }

        Intl.textdomain(GETTEXT_PACKAGE);
        internationalize(GETTEXT_PACKAGE, search_path_generator.get_locale_path(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR));

        Gst.init(ref args);

        // Suppress "Locale not supported by C library" by falling back gracefully.
        // This happens when the system locale (e.g. a custom locale on openSUSE)
        // isn't available in the C library or in AppImage's bundled glibc.
        if (Intl.setlocale(LocaleCategory.ALL, "") == null) {
            // Current locale is unsupported — try common fallbacks
            string? lang = Environment.get_variable("LANG");
            if (lang != null) {
                // Try the base language without encoding (e.g. "de_DE" from "de_DE.UTF-8")
                string base_lang = lang.split(".")[0];
                if (Intl.setlocale(LocaleCategory.ALL, base_lang + ".UTF-8") == null) {
                    Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");
                }
            }
        }

        // GTK4 does not support legacy GTK3-era IM modules.  If GTK_IM_MODULE
        // is set to a GTK3-only module (e.g. "cedilla", "xim"), GTK4 prints
        // "No IM module matching GTK_IM_MODULE=… found".  Unset only known
        // GTK3-only modules; leave ibus, fcitx5, etc. alone (GTK4 supports them).
        string? im_module = Environment.get_variable("GTK_IM_MODULE");
        if (im_module == "cedilla" || im_module == "xim") {
            Environment.unset_variable("GTK_IM_MODULE");
        }

        Gtk.init();
        
        // Ensure custom widget types are registered before loading templates that use them
        typeof(Dino.Ui.SizeRequestBox).ensure();
        typeof(Dino.Ui.NaturalSizeIncrease).ensure();
        typeof(Dino.Ui.SizingBin).ensure();

        Dino.Ui.Application app = new Dino.Ui.Application() { search_path_generator=search_path_generator };

#if WINDOWS
        string? exe_path = args.length > 0 ? args[0] : null;
        if (exe_path != null) {
             if (!exe_path.contains("\\") && !exe_path.contains("/")) {
                  exe_path = Environment.find_program_in_path(exe_path);
             }
             if (exe_path != null && !Path.is_absolute(exe_path)) {
                  exe_path = Path.build_filename(Environment.get_current_dir(), exe_path);
             }
        }
        string exe_dir = (exe_path != null) ? Path.get_dirname(exe_path) : Environment.get_current_dir();

        // Set ALL environment variables that the batch file used to set.
        // This makes dinox.exe fully self-contained — no .bat needed!

        // GTK/GLib resource paths
        Environment.set_variable("XDG_DATA_DIRS",
            Path.build_filename(exe_dir, "share"), true);
        Environment.set_variable("GSETTINGS_SCHEMA_DIR",
            Path.build_filename(exe_dir, "share", "glib-2.0", "schemas"), true);
        Environment.set_variable("GDK_PIXBUF_MODULE_FILE",
            Path.build_filename(exe_dir, "lib", "gdk-pixbuf-2.0", "2.10.0", "loaders.cache"), true);
        Environment.set_variable("GDK_PIXBUF_MODULEDIR",
            Path.build_filename(exe_dir, "lib", "gdk-pixbuf-2.0", "2.10.0", "loaders"), true);
        Environment.set_variable("GTK_PATH", exe_dir, true);

        // GStreamer plugin path
        Environment.set_variable("GST_PLUGIN_PATH",
            Path.build_filename(exe_dir, "lib", "gstreamer-1.0"), true);

        // Configure Icon Theme for portable Windows build
        var display = Gdk.Display.get_default();
        if (display != null) {
            var icon_theme = Gtk.IconTheme.get_for_display(display);
            // Assuming structure: dinox.exe -> share/icons (in dist folder)
            string icon_path = Path.build_filename(exe_dir, "share", "icons");
            if (FileUtils.test(icon_path, FileTest.IS_DIR)) {
                 icon_theme.add_search_path(icon_path);
                 message("Added icon path: %s", icon_path);
            } else {
                 // Try bin/../share/icons structure (standard installation)
                 icon_path = Path.build_filename(exe_dir, "..", "share", "icons");
                 if (FileUtils.test(icon_path, FileTest.IS_DIR)) {
                      icon_theme.add_search_path(icon_path);
                      message("Added icon path: %s", icon_path);
                 }
            }
        }

        // Force GnuTLS to find the CA bundle.
        // Portable mode: look next to the executable.
        // AppImage/system: probe well-known distro paths so that GnuTLS
        // works on openSUSE, Fedora, Arch, etc. — not just Debian/Ubuntu.
        string? trusted_certs = Environment.get_variable("GTLS_SYSTEM_CA_FILE");
        if (trusted_certs == null) {
            // Try standard relative paths for portable install
            string local_cert = Path.build_filename(exe_dir, "ssl", "certs", "ca-bundle.crt");
            if (FileUtils.test(local_cert, FileTest.EXISTS)) {
                Environment.set_variable("GTLS_SYSTEM_CA_FILE", local_cert, true);
                Environment.set_variable("SSL_CERT_FILE", local_cert, true);
                Environment.set_variable("SSL_CERT_DIR",
                    Path.build_filename(exe_dir, "ssl", "certs"), true);
                message("Set GTLS_SYSTEM_CA_FILE to %s", local_cert);
            } else {
                 string local_cert_flat = Path.build_filename(exe_dir, "ca-bundle.crt");
                 if (FileUtils.test(local_cert_flat, FileTest.EXISTS)) {
                    Environment.set_variable("GTLS_SYSTEM_CA_FILE", local_cert_flat, true);
                    Environment.set_variable("SSL_CERT_FILE", local_cert_flat, true);
                    message("Set GTLS_SYSTEM_CA_FILE to %s", local_cert_flat);
                 } else {
                    // Not portable mode on Windows — no bundled CA cert found.
                    // Windows GnuTLS typically uses the Schannel backend or
                    // a bundled ca-bundle.crt, so this is a warning case.
                    warning("No bundled CA certificate found next to executable");
                 }
            }
        }
        
        // Add exe directory AND bin/ folder to PATH.
        // The exe directory MUST be in PATH so that plugins loaded from
        // plugins/ can resolve their dependencies on our core DLLs
        // (libdino-0.dll, libxmpp-vala-0.dll, etc.) which live next to
        // dinox.exe.  Windows LoadLibrary does NOT search the parent
        // directory of a DLL being loaded.
        string bin_path = Path.build_filename(exe_dir, "bin");
        {
            string? old_path = Environment.get_variable("PATH");
            string new_path = exe_dir;
            if (FileUtils.test(bin_path, FileTest.IS_DIR)) {
                new_path = exe_dir + ";" + bin_path;
            }
            if (old_path != null) {
                new_path = new_path + ";" + old_path;
            }
            Environment.set_variable("PATH", new_path, true);
            message("PATH prepended: %s", exe_dir);
        }

        // Suppress "win32 session dbus binary not found" warning from GLib-GIO.
        // GApplication internally tries to connect to the session bus even with NON_UNIQUE,
        // but there is no DBus session bus daemon on Windows.
        Environment.set_variable("DBUS_SESSION_BUS_ADDRESS", "", true);
#endif

        // Probe system CA certificate locations on ALL platforms.
        // GnuTLS compiled on Ubuntu defaults to /etc/ssl/certs/ca-certificates.crt
        // which doesn't exist on openSUSE, Fedora, Alpine, etc.
        // On Windows the paths simply don't exist, so the loop is a harmless no-op.
        if (Environment.get_variable("GTLS_SYSTEM_CA_FILE") == null) {
            string[] system_ca_paths = {
                "/etc/ssl/certs/ca-certificates.crt",       // Debian, Ubuntu, Arch, Gentoo
                "/etc/pki/tls/certs/ca-bundle.crt",         // Fedora, RHEL, CentOS
                "/etc/ssl/ca-bundle.pem",                   // openSUSE
                "/var/lib/ca-certificates/ca-bundle.pem",   // openSUSE (alternative)
                "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", // Fedora p11-kit
                "/etc/ssl/cert.pem",                        // Alpine, macOS
            };
            foreach (string path in system_ca_paths) {
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    Environment.set_variable("GTLS_SYSTEM_CA_FILE", path, true);
                    message("Set GTLS_SYSTEM_CA_FILE to %s (system CA)", path);
                    break;
                }
            }
        }

        Plugins.Loader loader = new Plugins.Loader(app);
        app.plugin_loader = loader;

        app.run(args);
        
        loader.shutdown();
    } catch (Error e) {
        warning(@"Fatal error: $(e.message)");
    }
}

}
