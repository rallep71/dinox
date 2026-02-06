using Gee;

using Dino.Entities;

extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

[CCode (cname = "openpgp_fix_windows_stdio", cheader_filename = "gpgme_fix.h")]
extern void openpgp_fix_windows_stdio();

namespace Dino.Plugins.OpenPgp {

public class Plugin : Plugins.RootInterface, Object {
    public Dino.Application app;
    public Database db;
    public HashMap<Account, Module> modules = new HashMap<Account, Module>(Account.hash_func, Account.equals_func);
    public Xep0373KeyManager? xep0373_manager = null;

    private EncryptionListEntry list_entry;
    private ContactDetailsProvider contact_details_provider;

    public void registered(Dino.Application app) {
        this.app = app;

        // Use an app-scoped GnuPG keyring so that Panic-Wipe can safely destroy all OpenPGP material
        // without touching the user's global ~/.gnupg keyring.
        string openpgp_gnupg_home = Path.build_filename(Application.get_storage_dir(), "openpgp", "gnupg");
        if (DirUtils.create_with_parents(openpgp_gnupg_home, 0700) == -1) {
            warning("OpenPGP plugin disabled: could not create keyring dir '%s'", openpgp_gnupg_home);
            return;
        }

        // On Windows (MSYS2), get_storage_dir returns a Unix-style path (/c/...), but native GPG
        // expects Windows-style paths (C:\...). If we set GNUPGHOME to the Unix path, GPG fails.
        string env_gnupg_home = openpgp_gnupg_home;
        string? gpg_bindir = null;
#if WINDOWS
        openpgp_fix_windows_stdio();
        // Force backslashes for Windows paths to ensure native GPG compatibility
        // First handle potential MSYS path conversion if it starts with /c/
        if (openpgp_gnupg_home.has_prefix("/")) {
            if (openpgp_gnupg_home.length > 2 && openpgp_gnupg_home[2] == '/') { // /c/Users...
                string drive = openpgp_gnupg_home.substring(1, 1).up();
                env_gnupg_home = drive + ":\\" + openpgp_gnupg_home.substring(3).replace("/", "\\");
            } else {
                 env_gnupg_home = openpgp_gnupg_home.replace("/", "\\");
            }
            debug("Relocated GNUPGHOME for Windows: %s -> %s", openpgp_gnupg_home, env_gnupg_home);
        } else {
            // Already starts with Drive letter, just ensure backslashes
            env_gnupg_home = openpgp_gnupg_home.replace("/", "\\");
        }

        // Enable GPGME Debugging to file
        string debug_log = Path.build_filename(Application.get_storage_dir(), "gpgme_debug.log").replace("/", "\\");
        Environment.set_variable("GPGME_DEBUG", "9;" + debug_log, true);
        debug("GPGME Debug enabled: %s", debug_log);

        // Add GPG directory to PATH to ensure gpg-agent and other tools can be found
        string? gpg_bin = Environment.find_program_in_path("gpg");
        
        // On MINGW64, 'gpg' might be found at /usr/bin/gpg, but we need the native one at /mingw64/bin/gpg.exe
        // Prefer C:\msys64\mingw64\bin if it exists.
        if (FileUtils.test("C:/msys64/mingw64/bin/gpg.exe", FileTest.EXISTS)) {
             gpg_bindir = "C:\\msys64\\mingw64\\bin";
             // Force use of this gpg_bin for PATH setup
        } else if (gpg_bin != null) {
             // gpg_bin is something like C:\...\gpg.exe or /c/...
             // try to get dirname
             string? dn = Path.get_dirname(gpg_bin);
             if (dn != null && dn.has_prefix("/")) {
                 // convert to windows if needed, simplistic
                 // better: if we found explicit mingw64 above, use it.
             }
        }
        
        if (gpg_bindir != null) {
            string old_path = Environment.get_variable("PATH") ?? "";
            // Prepend to PATH so native GPG tools are found first
            Environment.set_variable("PATH", gpg_bindir + ";" + old_path, true);
            debug("Added GPG bin to PATH: %s", gpg_bindir);
        }
#endif
        Environment.set_variable("GNUPGHOME", env_gnupg_home, true);


        // Ensure gpg-agent is configured with pinentry for passphrase prompts
        // On Windows, we need pinentry-w32 or similar GUI pinentry
        string agent_conf_path = Path.build_filename(openpgp_gnupg_home, "gpg-agent.conf");
        try {
             // Configure gpg-agent to:
             // 1. Cache passphrases for a reasonable time (8 hours = 28800 seconds)
             // 2. Use GUI pinentry if available
             // 3. Disable smart card daemon (not needed, can cause issues)
             StringBuilder config = new StringBuilder();
             config.append("disable-scdaemon\n");
             config.append("default-cache-ttl 28800\n");
             config.append("max-cache-ttl 28800\n");
             
             // On Windows (MSYS2/MINGW64), try to use pinentry-w32 if available
             // This allows the user to enter their passphrase in a GUI dialog
#if WINDOWS
             string? pinentry_path = null;
             // Check common MSYS2 pinentry locations
             string[] pinentry_candidates = {
                 "C:\\msys64\\mingw64\\bin\\pinentry-w32.exe",
                 "C:\\msys64\\mingw64\\bin\\pinentry.exe",
                 "C:\\msys64\\usr\\bin\\pinentry-w32.exe",
                 "C:\\msys64\\usr\\bin\\pinentry.exe"
             };
             foreach (string candidate in pinentry_candidates) {
                 if (FileUtils.test(candidate, FileTest.EXISTS)) {
                     pinentry_path = candidate;
                     break;
                 }
             }
             if (pinentry_path != null) {
                 config.append("pinentry-program ");
                 config.append(pinentry_path);
                 config.append("\n");
                 debug("OpenPGP: Using pinentry: %s", pinentry_path);
             } else {
                 debug("OpenPGP: No pinentry found! Passphrase prompts may fail.");
                 debug("OpenPGP: Install pinentry with: pacman -S mingw-w64-x86_64-pinentry");
             }
#endif
             
             FileUtils.set_contents(agent_conf_path, config.str);
        } catch (Error e) {
             debug("Failed to write gpg-agent.conf: %s", e.message);
        }
        
        // Kill any existing gpg-agent to ensure it picks up the new config
#if WINDOWS
        try {
            // Use --homedir to ensure we target the correct agent
            string[] kill_args = { "gpgconf", "--homedir", env_gnupg_home, "--kill", "gpg-agent" };
            var subprocess = new Subprocess.newv(kill_args, SubprocessFlags.NONE);
            subprocess.wait();
            int exit_status = subprocess.get_if_exited() ? subprocess.get_exit_status() : -1;
            debug("OpenPGP: Killed gpg-agent (exit=%d)", exit_status);
            
            // Give it a moment to restart
            Thread.usleep(500000); // 500ms
            
            // Verify the gpg-agent.conf was written correctly
            string? conf_content = null;
            FileUtils.get_contents(agent_conf_path, out conf_content);
            debug("OpenPGP: gpg-agent.conf content:\n%s", conf_content);
        } catch (Error e) {
            debug("OpenPGP: Failed to restart gpg-agent: %s", e.message);
        }
#endif
        
        // CRITICAL: On Windows, sometimes setting the ENV var isn't enough for the spawned process if environment inheritance is weird,
        // OR GPG defaults to a different "socket dir" than "home dir".
        // We will pass --homedir explicitly in key_management_dialog.vala.

        try {
            this.db = new Database(Path.build_filename(Application.get_storage_dir(), "pgp.db"), app.db_key);
        } catch (Error e) {
            warning("OpenPGP plugin disabled: %s", e.message);
            return;
        }
        this.list_entry = new EncryptionListEntry(app.stream_interactor, db);
        this.contact_details_provider = new ContactDetailsProvider(app.stream_interactor);

        app.plugin_registry.register_encryption_list_entry(list_entry);
        app.plugin_registry.register_encryption_preferences_entry(new PgpPreferencesEntry(this));
        app.plugin_registry.register_contact_details_entry(contact_details_provider);
        app.stream_interactor.module_manager.initialize_account_modules.connect(on_initialize_account_modules);

        Manager.start(app.stream_interactor, db);
        
        // Initialize XEP-0373 key manager for PubSub-based key distribution
        // This enables interoperability with Conversations, Monocles, and other modern clients
        this.xep0373_manager = new Xep0373KeyManager(app.stream_interactor, db);
        debug("OpenPGP: XEP-0373 key manager initialized");
        
        // Connect XEP-0373 manager to the encryption list entry for async key fetching
        this.list_entry.set_xep0373_manager(this.xep0373_manager);
        
        // Connect XEP-0373 manager to the PGP manager for automatic key fetching
        Manager? pgp_manager = app.stream_interactor.get_module<Manager>(Manager.IDENTITY);
        if (pgp_manager != null) {
            pgp_manager.xep0373_manager = this.xep0373_manager;
            debug("OpenPGP: Connected XEP-0373 manager to PGP manager");
        }
        
        // When XEP-0373 receives a key, store it in the database so it can be used for encryption
        this.xep0373_manager.key_received.connect((account, jid, fingerprint, key_data) => {
            debug("OpenPGP: XEP-0373 key received for %s, fingerprint: %s", jid.to_string(), fingerprint);
            // Store the fingerprint as the contact key
            // XEP-0373 keys are already imported into GPG keyring by xep0373_key_manager
            db.set_contact_key(jid.bare_jid, fingerprint);
        });
        
        // Proactively fetch XEP-0373 keys when a conversation is activated
        // This ensures we have the contact's key before trying to encrypt
        app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).conversation_activated.connect((conversation) => {
            if (conversation == null) return;
            if (conversation.type_ == Conversation.Type.CHAT && this.xep0373_manager != null) {
                debug("OpenPGP: Conversation activated, requesting XEP-0373 keys for %s", conversation.counterpart.to_string());
                this.xep0373_manager.request_keys.begin(conversation.account, conversation.counterpart.bare_jid);
            }
        });
        
        app.stream_interactor.get_module<FileManager>(FileManager.IDENTITY).add_file_encryptor(new PgpFileEncryptor(app.stream_interactor));
        app.stream_interactor.get_module<FileManager>(FileManager.IDENTITY).add_file_decryptor(new PgpFileDecryptor());
        JingleFileHelperRegistry.instance.add_encryption_helper(Encryption.PGP, new JingleFileEncryptionHelperTransferOnly());

        internationalize(GETTEXT_PACKAGE, app.search_path_generator.get_locale_path(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR));
    }

    public void shutdown() { }

    private void on_initialize_account_modules(Account account, ArrayList<Xmpp.XmppStreamModule> modules) {
        string? key_id = db.get_account_key(account);
        
        // NOTE: We do NOT verify the key here synchronously anymore!
        // The Module.do_key_setup() handles this asynchronously in a background thread.
        // This prevents the app from hanging during startup if GPG is slow or unresponsive.
        // If the key is invalid, do_key_setup() will simply fail to enable signing,
        // and the user will see that OpenPGP is not working.
        
        debug("OpenPGP: Initializing modules for account %s, key_id: %s", 
              account.bare_jid.to_string(), key_id ?? "none");

        // Pre-cache the account key in background to avoid sync calls during message sending
        if (key_id != null) {
            var manager = app.stream_interactor.get_module<Manager>(Manager.IDENTITY);
            if (manager != null) {
                debug("OpenPGP: Pre-caching account key %s", key_id);
                manager.preload_key_async(key_id);
            }
        }

        // Add XEP-0027 module (legacy presence-based key signing)
        Module module = new Module(key_id);
        this.modules[account] = module;
        modules.add(module);
        
        // Add XEP-0373 module (modern PubSub-based key distribution)
        // This enables interoperability with Conversations, Monocles, and other modern clients
        modules.add(new Xmpp.Xep.OpenPgp.Module());
        
        // Add XEP-0374 module (modern OpenPGP message encryption)
        // This enables encrypted messaging with Conversations, Monocles, and other modern clients
        modules.add(new Xmpp.Xep.OpenPgpContent.Module());
        
        debug("OpenPGP: Added XEP-0027, XEP-0373, and XEP-0374 modules for account %s", account.bare_jid.to_string());
    }
}

}
