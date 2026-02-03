using Dino.Entities;
using Dino.Ui;
using Gst;

extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

namespace Dino {

void main(string[] args) {

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
        Intl.textdomain(GETTEXT_PACKAGE);
        internationalize(GETTEXT_PACKAGE, search_path_generator.get_locale_path(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR));

        Gst.init(ref args);
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

        // Force GnuTLS to find the ca-bundle if it's in the same directory (portable mode)
        string? trusted_certs = Environment.get_variable("GTLS_SYSTEM_CA_FILE");
        if (trusted_certs == null) {
            // Try standard relative paths for portable install
            string local_cert = Path.build_filename(exe_dir, "ssl", "certs", "ca-bundle.crt");
            if (FileUtils.test(local_cert, FileTest.EXISTS)) {
                Environment.set_variable("GTLS_SYSTEM_CA_FILE", local_cert, true);
                message("Set GTLS_SYSTEM_CA_FILE to %s", local_cert);
            } else {
                 string local_cert_flat = Path.build_filename(exe_dir, "ca-bundle.crt");
                 if (FileUtils.test(local_cert_flat, FileTest.EXISTS)) {
                    Environment.set_variable("GTLS_SYSTEM_CA_FILE", local_cert_flat, true);
                    message("Set GTLS_SYSTEM_CA_FILE to %s", local_cert_flat);
                 }
            }
        }
        
        // Add bin/ folder to PATH for portable tools (gpg.exe, tar.exe, etc.)
        string bin_path = Path.build_filename(exe_dir, "bin");
        if (FileUtils.test(bin_path, FileTest.IS_DIR)) {
            string? old_path = Environment.get_variable("PATH");
            if (old_path != null) {
                Environment.set_variable("PATH", bin_path + ";" + old_path, true);
            } else {
                Environment.set_variable("PATH", bin_path, true);
            }
            message("Added bin to PATH: %s", bin_path);
        }
#endif

        Plugins.Loader loader = new Plugins.Loader(app);
        app.plugin_loader = loader;

        app.run(args);
        
        loader.shutdown();
    } catch (Error e) {
        warning(@"Fatal error: $(e.message)");
    }
}

}
