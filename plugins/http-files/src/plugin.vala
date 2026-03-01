extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

namespace Dino.Plugins.HttpFiles {

public class Plugin : RootInterface, Object {

    public Dino.Application app;
    public FileProvider file_provider;
    public HttpFileSender file_sender;

    public void registered(Dino.Application app) {
        this.app = app;

        file_provider = new FileProvider(app.stream_interactor, app.db);
        file_sender = new HttpFileSender(app.stream_interactor, app.db);

        app.stream_interactor.get_module<FileManager>(FileManager.IDENTITY).add_provider(file_provider);
        app.stream_interactor.get_module<FileManager>(FileManager.IDENTITY).add_sender(file_sender);
    }

    public void shutdown() {
        if (file_provider != null) file_provider.shutdown();
        if (file_sender != null) file_sender.shutdown();
    }

    public void rekey_database(string new_key) throws Error {
        // No own database
    }

    public void checkpoint_database() {
        // No own database
    }
}

}

