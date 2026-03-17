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

        // Attach to parent console if launched from CMD/MSYS2.
        // With -mwindows the EXE is GUI subsystem (no console on double-click),
        // but when run from a terminal we want log output to be visible.
        SystrayWin32.attach_parent_console ();

        // Single-instance check: if another DinoX is running, activate it and exit.
        if (!SystrayWin32.check_single_instance ()) {
            Process.exit (0);
        }

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

        // Fontconfig — tell it to use our bundled config + fonts.
        string fc_conf = Path.build_filename(exe_dir, "etc", "fonts");
        Environment.set_variable("FONTCONFIG_PATH", fc_conf, true);

        // GStreamer plugin path — only look in our bundled dir, not system.
        string gst_plugin_dir = Path.build_filename(exe_dir, "lib", "gstreamer-1.0");
        Environment.set_variable("GST_PLUGIN_PATH", gst_plugin_dir, true);
        Environment.set_variable("GST_PLUGIN_SYSTEM_PATH", "", true);

        // GStreamer registry cache — use the pre-generated one next to the
        // plugins if it exists (created by update_dist.sh), otherwise fall
        // back to a user-data cache so subsequent starts are still fast.
        string bundled_registry = Path.build_filename(gst_plugin_dir, "registry.bin");
        if (FileUtils.test(bundled_registry, FileTest.EXISTS)) {
            Environment.set_variable("GST_REGISTRY", bundled_registry, true);
        } else {
            string gst_cache_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
            DirUtils.create_with_parents(gst_cache_dir, 0700);
            Environment.set_variable("GST_REGISTRY",
                Path.build_filename(gst_cache_dir, "gstreamer-registry.bin"), true);
        }

        // Force GnuTLS to find the CA bundle.
        // Strategy: merge Windows system cert store + bundled MSYS2 ca-bundle.crt
        // so that CAs trusted by *either* source are accepted.  This avoids the
        // common problem where the MSYS2 bundle is outdated (e.g. missing ISRG
        // Root X1) even though Windows itself trusts Let's Encrypt.
        string? trusted_certs = Environment.get_variable("GTLS_SYSTEM_CA_FILE");
        if (trusted_certs == null) {
            string? ca_path = null;

            // Locate bundled CA bundle from MSYS2
            string local_cert = Path.build_filename(exe_dir, "ssl", "certs", "ca-bundle.crt");
            string local_cert_flat = Path.build_filename(exe_dir, "ca-bundle.crt");
            string? bundled_path = null;
            if (FileUtils.test(local_cert, FileTest.EXISTS)) {
                bundled_path = local_cert;
            } else if (FileUtils.test(local_cert_flat, FileTest.EXISTS)) {
                bundled_path = local_cert_flat;
            }

            // Export Windows system ROOT certificates and merge with bundled bundle
            string cache_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
            string cached_pem = Path.build_filename(cache_dir, "merged-ca-bundle.pem");
            bool have_windows = CertstoreWin32.export_pem(cached_pem);

            if (have_windows && bundled_path != null) {
                // Append bundled Mozilla roots for maximum coverage
                try {
                    uint8[] bundled_data;
                    FileUtils.get_data(bundled_path, out bundled_data);
                    var file = File.new_for_path(cached_pem);
                    var os = file.append_to(FileCreateFlags.NONE);
                    os.write(bundled_data);
                    os.close();
                } catch (Error e) {
                    warning("Failed to append bundled CA certs: %s", e.message);
                }
                ca_path = cached_pem;
                message("Merged Windows root certs + %s → %s", bundled_path, cached_pem);
            } else if (have_windows) {
                ca_path = cached_pem;
                message("Using Windows root certificates: %s", cached_pem);
            } else if (bundled_path != null) {
                ca_path = bundled_path;
            } else {
                warning("No CA certificates available — TLS connections will fail");
            }

            if (ca_path != null) {
                Environment.set_variable("GTLS_SYSTEM_CA_FILE", ca_path, true);
                Environment.set_variable("SSL_CERT_FILE", ca_path, true);
                string ca_dir = Path.get_dirname(ca_path);
                Environment.set_variable("SSL_CERT_DIR", ca_dir, true);
                message("Set GTLS_SYSTEM_CA_FILE to %s", ca_path);

                // Explicitly set the default TLS trust database from our merged
                // CA bundle.  Env vars alone are unreliable: glib-networking on
                // MSYS2/MinGW may use a backend (OpenSSL/SChannel) that ignores
                // GTLS_SYSTEM_CA_FILE.  This forces ALL TlsConnections to verify
                // against our merged Windows + Mozilla root certificates.
                try {
                    TlsDatabase tls_db = TlsFileDatabase.@new(ca_path);
                    TlsBackend.get_default().set_default_database(tls_db);
                    message("TLS trust database loaded: %s", ca_path);
                } catch (Error e) {
                    warning("Failed to load TLS database from %s: %s", ca_path, e.message);
                }
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

        message("Initializing GStreamer…");
        Gst.init(ref args);
        message("GStreamer initialized");

#if _WIN32
        // Log GStreamer plugin summary for debugging
        var registry = Gst.Registry.@get();
        var plugins = registry.get_plugin_list();
        message("GStreamer: %u plugins loaded from %s",
                plugins.length(),
                Environment.get_variable("GST_PLUGIN_PATH") ?? "(default)");
        // Check critical elements for video playback
        string[] critical = {"playbin", "videoconvert", "autoaudiosink",
                             "qtdemux", "matroskademux", "avdec_h264",
                             "openh264dec", "avdec_aac", "opusdec"};
        foreach (string el in critical) {
            var factory = Gst.ElementFactory.find(el);
            if (factory == null) {
                warning("GStreamer: MISSING element '%s' — video playback may fail!", el);
            }
        }
#endif

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

        message("Initializing GTK…");
        Gtk.init();
        message("GTK initialized");
        
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
