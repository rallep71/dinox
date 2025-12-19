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
        Dino.Ui.Application app = new Dino.Ui.Application() { search_path_generator=search_path_generator };
        Plugins.Loader loader = new Plugins.Loader(app);
        app.plugin_loader = loader;

        app.run(args);
        
        loader.shutdown();
    } catch (Error e) {
        warning(@"Fatal error: $(e.message)");
    }
}

}
