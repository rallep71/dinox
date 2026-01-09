using Dino;
using GLib;
using Dino.Entities;
using Gee;

namespace Dino.Plugins.TorManager {

    public class TorManager : Object, StreamInteractionModule {
        public const string IDENTITY_STRING = "tor-manager";
        public static ModuleIdentity<TorManager> IDENTITY = new ModuleIdentity<TorManager>(IDENTITY_STRING);

        public string id { get { return IDENTITY_STRING; } }


        public TorController controller { get; private set; }
        public bool is_enabled { get; private set; default = false; }
        private StreamInteractor stream_interactor;
        private Database db;
        private bool is_shutting_down = false;

        public TorManager(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;
            controller = new TorController();
            controller.process_exited.connect(on_process_exited);
            
            // Restore state
            restore_state();
        }

        public void prepare_shutdown() {
            is_shutting_down = true;
        }

        private void restore_state() {
            try {
                // Iterate all settings to avoid 'where' syntax compilation issues
                foreach (var row in db.settings.select()) {
                    string key = row[db.settings.key];
                    string? val = row[db.settings.value];
                    
                    if (key == "tor_manager_enabled") {
                        stderr.printf("TorManager: restore_state() - DB value for 'tor_manager_enabled': %s\n", val ?? "null");
                        if (val == "true") {
                            is_enabled = true;
                        }
                    } else if (key == "tor_manager_bridges") {
                        if (val != null) {
                            controller.bridge_lines = val;
                        }
                    }
                }
                
                if (is_enabled) {
                    stderr.printf("TorManager: state is ENABLED. Starting Tor...\n");
                    start_tor(false); // don't re-apply proxy settings on startup loop, they are persistent
                } else {
                    // CRITICAL FIX: If state is OFF, strictly ensure no accounts are left in SOCKS5 mode.
                    stderr.printf("TorManager: state is DISABLED. Ensuring clear-net (DB Cleanup)...\n");
                    cleanup_lingering_proxies();
                }
            } catch (Error e) {
                warning("TorManager: restore_state Error: %s", e.message);
            }
        }


        private void cleanup_lingering_proxies() {
            try {
                // 1. Collect targets first to avoid DB locking/iterator invalidation during updates
                var targets = new Gee.ArrayList<int>();
                
                foreach (var row in db.account.select()) {
                    string ptype = row[db.account.proxy_type];
                    if (ptype == "socks5") {
                        targets.add(row[db.account.id]);
                    }
                }

                // 2. Remediate targets
                foreach (int id_val in targets) {
                     warning("TorManager: cleanup_lingering_proxies - Found lingering SOCKS5 on account ID %d. Remediating...", id_val);
                        
                    // Fix DB
                    db.account.update()
                        .set(db.account.proxy_type, "none")
                        .set(db.account.proxy_host, "")
                        .set(db.account.proxy_port, 0)
                        .with(db.account.id, "=", id_val)
                        .perform();

                    // Fix RAM / Active Connections
                    if (stream_interactor != null) {
                        var accounts = stream_interactor.get_accounts();
                        foreach (var account in accounts) {
                            if (account.id == id_val) {
                                warning("TorManager: Forcing RAM disconnect for %s", account.bare_jid.to_string());
                                account.proxy_type = "none";
                                account.proxy_host = "";
                                account.proxy_port = 0;
                                reconnect_account.begin(account);
                            }
                        }
                    }
                }
            } catch (Error e) {
                warning("TorManager: cleanup_lingering_proxies Error: %s", e.message);
            }
        }
        
        private void on_process_exited(int status) {
            if (is_shutting_down) {
                 stderr.printf("TorManager: Process exited during application shutdown (status %d). Ignoring.\n", status);
                 return;
            }

            stderr.printf("TorManager: [CRITICAL] Tor exited with status %d. Initiating emergency proxy removal.\n", status);
            // Force disable, regardless of current state check, to ensure cleanup happens
            set_enabled(false); 
        }
        
        public void set_bridges(string bridges) {
            stderr.printf("TorManager: Updating bridges settings.\n");
            controller.bridge_lines = bridges;
             db.settings.upsert()
                    .value(db.settings.key, "tor_manager_bridges", true)
                    .value(db.settings.value, bridges)
                    .perform();
        }

        public void set_enabled(bool enabled) {
            stderr.printf("TorManager: set_enabled(%s) called. Current state: %s\n", enabled.to_string(), is_enabled.to_string());
            is_enabled = enabled;
            // Update DB
            var val = enabled ? "true" : "false";
            
            db.settings.upsert()
                    .value(db.settings.key, "tor_manager_enabled", true)
                    .value(db.settings.value, val)
                    .perform();

            if (enabled) {
                stderr.printf("TorManager: Starting Tor...\n");
                start_tor(true);
            } else {
                stderr.printf("TorManager: Stopping Tor and cleaning up...\n");
                stop_tor(true);
            }
        }

        public void start_tor(bool apply_proxy = false) {
            controller.start.begin();
            if (apply_proxy) apply_proxy_to_accounts(true);
        }

        public void stop_tor(bool remove_proxy = false) {
            controller.stop();
            // ALWAYS try to remove proxy if requested, even if we think it's stopped
            if (remove_proxy) {
                // Ensure the database and RAM are consistent with "Tor OFF"
                // This prevents "Zombie connection" where proxy is ON but Tor is dead
                stderr.printf("TorManager: stop_tor calling cleanup_lingering_proxies() to fix RAM/DB mismatch.\n");
                cleanup_lingering_proxies();
            }

        }

        public void apply_proxy_to_accounts(bool enable_tor) {
            
            if (enable_tor) {
                var accounts = stream_interactor.get_accounts();
                warning("TorManager: ENABLE sequence - Found %d managed accounts.", accounts.size);
                foreach (var account in accounts) {
                    warning("TorManager: Setting SOCKS5 for %s", account.bare_jid.to_string());
                    account.proxy_type = "socks5";
                    account.proxy_host = "127.0.0.1";
                    account.proxy_port = controller.socks_port;
                    reconnect_account.begin(account);
                }
            } else {
                // DISABLE sequence - use the robust cleanup logic we unified
                stderr.printf("TorManager: DISABLE sequence - invoking robust cleanup_lingering_proxies()\n");
                cleanup_lingering_proxies();
            }
        }

        private async void reconnect_account(Account account) {
             // only reconnect if already connected or connecting
             var state = stream_interactor.connection_manager.get_state(account);
             if (state == ConnectionManager.ConnectionState.CONNECTED || state == ConnectionManager.ConnectionState.CONNECTING) {
                 debug("Disconnecting account %s to apply Tor settings...", account.bare_jid.to_string());
                 yield stream_interactor.connection_manager.disconnect_account(account);
                 
                 // Wait a bit using Glib Timeout (async compatible)
                 yield new Request(100).await();
                 
                 debug("Reconnecting account %s through Tor...", account.bare_jid.to_string());
                 stream_interactor.connect_account(account);
             }
        }
        
        // Helper class for async wait
        private class Request : Object {
            private uint interval;
            public Request(uint interval) { this.interval = interval; }
            public async void await() {
                Timeout.add(interval, () => {
                    await.callback();
                    return false;
                });
                yield;
            }
        }
    }
}
