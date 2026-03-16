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

#if WINDOWS
        // Windows environment setup — MUST happen BEFORE Gst.init() and Gtk.init()
        // so that GTK4 can find schemas, pixbuf loaders, and GStreamer its plugins.
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

        // Publish exe_dir so plugins can find bundled files without relying on cwd
        Environment.set_variable("DINOX_EXE_DIR", exe_dir, true);

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

        // Force GnuTLS to find the CA bundle.
        // Strategy: (1) bundled ca-bundle.crt, (2) export Windows cert store
        string? trusted_certs = Environment.get_variable("GTLS_SYSTEM_CA_FILE");
        if (trusted_certs == null) {
            string? ca_path = null;

            // Try bundled CA bundle first
            string local_cert = Path.build_filename(exe_dir, "ssl", "certs", "ca-bundle.crt");
            string local_cert_flat = Path.build_filename(exe_dir, "ca-bundle.crt");
            if (FileUtils.test(local_cert, FileTest.EXISTS)) {
                ca_path = local_cert;
            } else if (FileUtils.test(local_cert_flat, FileTest.EXISTS)) {
                ca_path = local_cert_flat;
            }

            // Fallback: export Windows system certificate store to a cached PEM file
            if (ca_path == null) {
                string cache_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
                string cached_pem = Path.build_filename(cache_dir, "windows-ca-bundle.pem");
                if (CertstoreWin32.export_pem(cached_pem)) {
                    ca_path = cached_pem;
                    message("Exported Windows root certificates to %s", cached_pem);
                } else {
                    warning("No CA certificates available — TLS connections will fail");
                }
            }

            if (ca_path != null) {
                Environment.set_variable("GTLS_SYSTEM_CA_FILE", ca_path, true);
                Environment.set_variable("SSL_CERT_FILE", ca_path, true);
                string ca_dir = Path.get_dirname(ca_path);
                Environment.set_variable("SSL_CERT_DIR", ca_dir, true);
                message("Set GTLS_SYSTEM_CA_FILE to %s", ca_path);
            }
        }

        // Add exe directory AND bin/ folder to PATH so DLLs and tools are found
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

        // Suppress "win32 session dbus binary not found" warning
        Environment.set_variable("DBUS_SESSION_BUS_ADDRESS", "", true);
#endif

        Gst.init(ref args);

        // Suppress "Locale not supported by C library" by falling back gracefully.
        // This happens when the system locale (e.g. a custom locale on openSUSE)
        // isn't available in the C library or in AppImage's bundled glibc.
        // We must also update LANG so that Gtk.init() (which re-reads the
        // environment) does not fail with the same warning.
        if (Intl.setlocale(LocaleCategory.ALL, "") == null) {
            string? lang = Environment.get_variable("LANG");
            string? working_locale = null;
            if (lang != null) {
                string base_lang = lang.split(".")[0];
                string candidate = base_lang + ".UTF-8";
                if (Intl.setlocale(LocaleCategory.ALL, candidate) != null) {
                    working_locale = candidate;
                }
            }
            if (working_locale == null) {
                Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");
                working_locale = "C.UTF-8";
            }
            // Update environment so Gtk.init() picks up the working locale
            Environment.set_variable("LC_ALL", working_locale, true);
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
        // Configure Icon Theme for portable Windows build (needs Gdk.Display → after Gtk.init)
        var display = Gdk.Display.get_default();
        if (display != null) {
            var icon_theme = Gtk.IconTheme.get_for_display(display);
            string icon_path = Path.build_filename(exe_dir, "share", "icons");
            if (FileUtils.test(icon_path, FileTest.IS_DIR)) {
                 icon_theme.add_search_path(icon_path);
                 message("Added icon path: %s", icon_path);
            } else {
                 icon_path = Path.build_filename(exe_dir, "..", "share", "icons");
                 if (FileUtils.test(icon_path, FileTest.IS_DIR)) {
                      icon_theme.add_search_path(icon_path);
                      message("Added icon path: %s", icon_path);
                 }
            }
        }
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
