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
        public bool use_bridges { get; private set; default = true; }
        public bool force_firewall_ports { get; private set; default = true; }
        private StreamInteractor stream_interactor;
        private Database db;
        private bool is_shutting_down = false;
        private bool is_starting_up = false;  // True during initial restore_state → start_tor sequence
        private int retry_count = 0;
        private const int MAX_RETRIES = 2;

        // Fallback bridges to bootstrap connection if blocked
        private const string BOOTSTRAP_BRIDGES = """# Default Bootstrap Bridges
obfs4 192.95.36.142:443 CDF2E852BF539B82BC10E27E9115A342BCFE8D62 cert=qUVQ0gLi21iFjhTCNAHJOXym3xbQ1wDfN9Xj96zZlvrbd/t5kL7x8Lz7qU15DrNPbYvsgw iat-mode=0
obfs4 198.245.60.50:443 6C61208D644265A16CB0C7E835787C1D8429EC08 cert=sT/u/T1uA+xW59mZ+6Y9t6GjkFcwI5z5p5u5i5j5k5l5m5n5o5p5q5r5s5t5u5v5 iat-mode=0
""";

        public TorManager(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;
            controller = new TorController();
            controller.process_exited.connect(on_process_exited);
            controller.bootstrap_status.connect((percent, summary) => {
                if (percent >= 100) {
                    debug("TorManager: Tor fully bootstrapped. Resetting retry count.");
                    retry_count = 0;
                }
            });
            
            this.stream_interactor.account_added.connect(on_account_added);

            // Restore state
            restore_state();
        }

        private void on_account_added(Account account) {
            if (is_enabled) {
                // Always set proxy settings so the first connection attempt goes through Tor.
                // If Tor isn't ready yet, the connection will fail and retry.
                int port = controller.socks_port;
                debug("TorManager: New account added (%s). Setting proxy to 127.0.0.1:%d (Tor running: %s)",
                       account.bare_jid.to_string(), port, controller.is_running.to_string());
                account.proxy_type = "socks5";
                account.proxy_host = "127.0.0.1";
                account.proxy_port = port;
                
                db.account.update()
                        .set(db.account.proxy_type, "socks5")
                        .set(db.account.proxy_host, "127.0.0.1")
                        .set(db.account.proxy_port, port)
                        .with(db.account.id, "=", account.id)
                        .perform();
            }
        }

        public void prepare_shutdown() {
            is_shutting_down = true;
        }

        private void restore_state() {
            // Iterate all settings to avoid 'where' syntax compilation issues
            foreach (var row in db.settings.select()) {
                string key = row[db.settings.key];
                string? val = row[db.settings.value];
                
                if (key == "tor_manager_enabled") {
                    debug("TorManager: restore_state() - DB value for 'tor_manager_enabled': %s", val ?? "null");
                    if (val == "true") {
                        is_enabled = true;
                    }
                } else if (key == "tor_manager_bridges") {
                    if (val != null) {
                        controller.bridge_lines = val;
                    }
                } else if (key == "tor_manager_use_bridges") {
                    if (val == "true") use_bridges = true;
                    else if (val == "false") use_bridges = false;
                } else if (key == "tor_manager_firewall_ports") {
                    if (val == "true") force_firewall_ports = true;
                    else if (val == "false") force_firewall_ports = false;
                }
            }
            
            // Sync controller
            controller.use_bridges = use_bridges;
            controller.force_firewall_ports = force_firewall_ports;

            // If bridges are not set in DB (first run?), populate with bootstrap bridges
            bool bridges_exist = false;
                foreach (var row in db.settings.select()) {
                if (row[db.settings.key] == "tor_manager_bridges") {
                    bridges_exist = true;
                    break;
                }
            }
            
            if (!bridges_exist) {
                    controller.bridge_lines = BOOTSTRAP_BRIDGES;
                    // Don't save to DB yet to allow "clean" revert? 
                    // No, better to persist it so user sees it.
                    db.settings.upsert()
                    .value(db.settings.key, "tor_manager_bridges", true)
                    .value(db.settings.value, BOOTSTRAP_BRIDGES)
                    .perform();
            }

            if (is_enabled) {
                debug("TorManager: state is ENABLED. Starting Tor...");
                is_starting_up = true;
                // FORCE apply proxy settings on startup (true) because the port might have changed dynamically (e.g. 9155 -> 9156)
                start_tor.begin(true, (obj, res) => {
                    is_starting_up = false;
                });
            } else {
                // CRITICAL FIX: If state is OFF, strictly ensure no accounts are left in SOCKS5 mode.
                debug("TorManager: state is DISABLED. Ensuring clear-net (DB Cleanup)...");
                cleanup_lingering_proxies.begin();
            }
        }


        private async void cleanup_lingering_proxies() {
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
                    debug("TorManager: cleanup_lingering_proxies - Found lingering SOCKS5 on account ID %d. Remediating...", id_val);
                    
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
                            debug("TorManager: Forcing RAM disconnect for %s", account.bare_jid.to_string());
                            account.proxy_type = "none";
                            account.proxy_host = "";
                            account.proxy_port = 0;
                            reconnect_account.begin(account);
                        }
                    }
                }
            }
        }
        
        private void on_process_exited(int status) {
            if (is_shutting_down) {
                 debug("TorManager: Process exited during application shutdown (status %d). Ignoring.", status);
                 return;
            }

            if (retry_count < MAX_RETRIES) {
                retry_count++;
                warning("TorManager: Tor exited unexpectedly with status %d so we are trying to fix it. Attempt %d/%d. Cleaning state...", status, retry_count, MAX_RETRIES);
                
                // Attempt to clean state which might be corrupted ("Acting on config options left us in a broken state")
                controller.clean_state();
                
                // Restart
                start_tor.begin(true);
                return;
            }

            warning("TorManager: [CRITICAL] Tor exited with status %d. Retries exhausted. Initiating emergency proxy removal.", status);
            // Force disable, regardless of current state check, to ensure cleanup happens
            set_enabled.begin(false); 
        }
        
        public async void set_bridges(string bridges) {
            debug("TorManager: Updating bridges settings.");
            controller.bridge_lines = bridges;
             db.settings.upsert()
                    .value(db.settings.key, "tor_manager_bridges", true)
                    .value(db.settings.value, bridges)
                    .perform();
            
            // If running, restart to apply
            if (is_enabled) {
                yield stop_tor(false);
                yield start_tor(true);
            }
        }

        public async void update_use_bridges(bool use) {
            if (use_bridges == use) return;
            use_bridges = use;
            controller.use_bridges = use;
            
            db.settings.upsert()
                    .value(db.settings.key, "tor_manager_use_bridges", true)
                    .value(db.settings.value, use ? "true" : "false")
                    .perform();
            
             // If running, restart to apply
            if (is_enabled) {
                yield stop_tor(false);
                yield start_tor(true);
            }
        }

        public async void update_firewall_ports(bool use) {
            if (force_firewall_ports == use) return;
            force_firewall_ports = use;
            controller.force_firewall_ports = use;
            
            db.settings.upsert()
                    .value(db.settings.key, "tor_manager_firewall_ports", true)
                    .value(db.settings.value, use ? "true" : "false")
                    .perform();

            // If running, restart to apply
            if (is_enabled) {
                yield stop_tor(false);
                yield start_tor(true);
            }
        }

        public async void set_enabled(bool enabled) {
            debug("TorManager: set_enabled(%s) called. Current state: %s", enabled.to_string(), is_enabled.to_string());
            is_enabled = enabled;
            // Update DB
            var val = enabled ? "true" : "false";
            
            db.settings.upsert()
                    .value(db.settings.key, "tor_manager_enabled", true)
                    .value(db.settings.value, val)
                    .perform();

            if (enabled) {
                debug("TorManager: Starting Tor...");
                yield start_tor(true);
            } else {
                debug("TorManager: Stopping Tor and cleaning up...");
                yield stop_tor(true);
            }
        }

        public async void start_tor(bool apply_proxy = false) {
            yield controller.start();
            if (apply_proxy) {
                // Wait for Tor to fully bootstrap before applying proxy settings.
                // Otherwise, XMPP connections attempt to use the SOCKS5 proxy before
                // Tor has built circuits, resulting in "connection refused" errors.
                bool bootstrapped = yield wait_for_bootstrap(60);
                if (bootstrapped) {
                    debug("TorManager: Tor bootstrapped, applying proxy settings now.");
                    apply_proxy_to_accounts(true);
                } else {
                    warning("TorManager: Tor bootstrap timed out. Applying proxy anyway (will retry on connect).");
                    apply_proxy_to_accounts(true);
                }
            }
        }

        /**
         * Wait until the TorController emits bootstrap_status with percent >= 100,
         * or until timeout_seconds expires. Returns true if bootstrap completed.
         */
        private async bool wait_for_bootstrap(int timeout_seconds) {
            if (!controller.is_running) return false;

            bool completed = false;
            ulong handler_id = 0;
            uint timeout_id = 0;

            handler_id = controller.bootstrap_status.connect((percent, summary) => {
                if (percent >= 100) {
                    completed = true;
                    wait_for_bootstrap.callback();
                }
            });

            timeout_id = Timeout.add_seconds((uint) timeout_seconds, () => {
                timeout_id = 0;
                wait_for_bootstrap.callback();
                return Source.REMOVE;
            });

            yield;

            // Cleanup
            if (handler_id != 0) {
                SignalHandler.disconnect(controller, handler_id);
            }
            if (timeout_id != 0) {
                Source.remove(timeout_id);
            }

            return completed;
        }

        public async void stop_tor(bool remove_proxy = false) {
            controller.stop();
            // ALWAYS try to remove proxy if requested, even if we think it's stopped
            if (remove_proxy) {
                // Ensure the database and RAM are consistent with "Tor OFF"
                // This prevents "Zombie connection" where proxy is ON but Tor is dead
                debug("TorManager: stop_tor calling cleanup_lingering_proxies() to fix RAM/DB mismatch.");
                yield cleanup_lingering_proxies();
            }

        }

        public void apply_proxy_to_accounts(bool enable_tor) {
            
            if (enable_tor) {
                var accounts = stream_interactor.get_accounts();
                debug("TorManager: ENABLE sequence - Found %d managed accounts. Applying Port: %d", accounts.size, controller.socks_port);
                foreach (var account in accounts) {
                    bool port_changed = (account.proxy_port != controller.socks_port);
                    
                    // 1. Update DB to persist settings
                    db.account.update()
                        .set(db.account.proxy_type, "socks5")
                        .set(db.account.proxy_host, "127.0.0.1")
                        .set(db.account.proxy_port, controller.socks_port)
                        .with(db.account.id, "=", account.id)
                        .perform();

                    // 2. Update RAM object
                    account.proxy_type = "socks5";
                    account.proxy_host = "127.0.0.1";
                    account.proxy_port = controller.socks_port;
                    
                    // 3. Only reconnect if the account is already connected/connecting
                    //    (skip during startup — accounts will connect with proxy settings
                    //    that we already set via on_account_added)
                    var state = stream_interactor.connection_manager.get_state(account);
                    if (state == ConnectionManager.ConnectionState.CONNECTED ||
                        state == ConnectionManager.ConnectionState.CONNECTING) {
                        if (port_changed) {
                            debug("TorManager: Port changed for %s, reconnecting through 127.0.0.1:%d",
                                  account.bare_jid.to_string(), controller.socks_port);
                            reconnect_account.begin(account);
                        } else {
                            debug("TorManager: %s already configured for port %d, no reconnect needed",
                                  account.bare_jid.to_string(), controller.socks_port);
                        }
                    } else {
                        debug("TorManager: %s not connected yet (state: %s), proxy settings applied for next connect",
                              account.bare_jid.to_string(), state.to_string());
                    }
                }
            } else {
                // DISABLE sequence - use the robust cleanup logic we unified
                debug("TorManager: DISABLE sequence - invoking robust cleanup_lingering_proxies()");
                cleanup_lingering_proxies.begin();
            }
        }

        private async void reconnect_account(Account account) {
             // Force reconnect even if disconnected, to ensure new proxy settings are picked up immediately
             var state = stream_interactor.connection_manager.get_state(account);
             debug("TorManager: Reconnecting %s (Current State: %s)", account.bare_jid.to_string(), state.to_string());
             
             if (state == ConnectionManager.ConnectionState.CONNECTED || state == ConnectionManager.ConnectionState.CONNECTING) {
                 debug("Disconnecting account %s to apply Tor settings...", account.bare_jid.to_string());
                 yield stream_interactor.connection_manager.disconnect_account(account);
                 
                 // Wait a bit using Glib Timeout (async compatible)
                 yield new Request(250).await();
             }
             
             debug("Reconnecting account %s through Tor...", account.bare_jid.to_string());
             stream_interactor.connect_account(account);
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
