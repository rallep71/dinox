/*
 * DinoX MQTT Plugin
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 *
 * Two connection modes:
 *
 *   1. Per-Account MQTT  — each XMPP account can connect to its domain's
 *      MQTT broker (ejabberd mod_mqtt / Prosody mod_pubsub_mqtt).
 *      Enabled per account, uses XMPP credentials or explicit config.
 *
 *   2. Standalone MQTT   — a single connection to any MQTT broker,
 *      independent of XMPP accounts (Mosquitto, HiveMQ, HA, …).
 *
 * Phase 1 Configuration (environment variables, until Settings UI):
 *
 *   Per-Account mode (connects when XMPP account goes online):
 *     DINOX_MQTT_ACCOUNT   — "1" to enable per-account MQTT
 *                            (uses account domain as broker host)
 *     DINOX_MQTT_PORT      — broker port (default: 1883)
 *     DINOX_MQTT_TLS       — "1" to enable TLS
 *     DINOX_MQTT_TOPICS    — comma-separated topic filters
 *
 *   Standalone mode (connects once, first XMPP account triggers it):
 *     DINOX_MQTT_HOST      — broker hostname/IP (enables standalone)
 *     DINOX_MQTT_PORT      — broker port (default: 1883)
 *     DINOX_MQTT_TLS       — "1" to enable TLS
 *     DINOX_MQTT_USER      — username (optional)
 *     DINOX_MQTT_PASS      — password (optional)
 *     DINOX_MQTT_TOPICS    — comma-separated topic filters
 *
 *   If both DINOX_MQTT_HOST and DINOX_MQTT_ACCOUNT are set,
 *   standalone mode takes precedence (one broker, not per-account).
 *
 * Requires: libmosquitto-dev
 */

using Dino.Entities;
using Gee;
using Xmpp;

namespace Dino.Plugins.Mqtt {

public class Plugin : RootInterface, Object {

    public Dino.Application app;

    /* Per-account MQTT connections */
    private HashMap<string, MqttClient> account_clients =
        new HashMap<string, MqttClient>();  /* key = bare_jid string */

    /* Standalone MQTT connection (independent of accounts) */
    private MqttClient? standalone_client = null;

    /* Track connect-in-progress to prevent duplicate async calls */
    private HashSet<string> connecting_accounts = new HashSet<string>();
    private bool standalone_connecting = false;

    /* Mode flags */
    private bool mode_standalone = false;   /* DINOX_MQTT_HOST set */
    private bool mode_per_account = false;  /* DINOX_MQTT_ACCOUNT=1 */

    /* Env-based config (Phase 1) */
    private string? cfg_host = null;
    private int cfg_port = 1883;
    private bool cfg_tls = false;
    private string? cfg_user = null;
    private string? cfg_pass = null;
    private string[] cfg_topics = {};

    /* ── RootInterface ─────────────────────────────────────────────── */

    public void registered(Dino.Application app) {
        this.app = app;

        /* Read config from environment */
        cfg_host = Environment.get_variable("DINOX_MQTT_HOST");
        string? port_s = Environment.get_variable("DINOX_MQTT_PORT");
        if (port_s != null) cfg_port = int.parse(port_s);
        cfg_tls = Environment.get_variable("DINOX_MQTT_TLS") == "1";
        cfg_user = Environment.get_variable("DINOX_MQTT_USER");
        cfg_pass = Environment.get_variable("DINOX_MQTT_PASS");
        string? topics_s = Environment.get_variable("DINOX_MQTT_TOPICS");
        if (topics_s != null) {
            cfg_topics = topics_s.split(",");
        }

        /* Determine mode */
        mode_standalone = (cfg_host != null && cfg_host != "");
        mode_per_account = Environment.get_variable("DINOX_MQTT_ACCOUNT") == "1";

        /* Standalone overrides per-account */
        if (mode_standalone && mode_per_account) {
            message("MQTT: Both DINOX_MQTT_HOST and DINOX_MQTT_ACCOUNT set " +
                    "— using standalone mode");
            mode_per_account = false;
        }

        if (mode_standalone) {
            message("MQTT plugin: standalone mode — broker %s:%d (tls=%s)",
                    cfg_host, cfg_port, cfg_tls.to_string());
        } else if (mode_per_account) {
            message("MQTT plugin: per-account mode — will use each " +
                    "account's domain as MQTT broker");
        } else {
            message("MQTT plugin: registered (idle — set DINOX_MQTT_HOST " +
                    "or DINOX_MQTT_ACCOUNT=1 to auto-connect)");
        }

        /* Listen for XMPP connection state changes */
        app.stream_interactor.connection_manager.connection_state_changed.connect(
            on_xmpp_connection_state_changed);
    }

    public void shutdown() {
        /* Disconnect standalone */
        if (standalone_client != null) {
            standalone_client.disconnect_sync();
            standalone_client = null;
        }

        /* Disconnect all per-account clients */
        foreach (var entry in account_clients.entries) {
            entry.value.disconnect_sync();
        }
        account_clients.clear();

        message("MQTT plugin: shutdown");
    }

    public void rekey_database(string new_key) throws Error {
        /* No database in this plugin — no-op */
    }

    public void checkpoint_database() {
        /* No database in this plugin — no-op */
    }

    /* ── XMPP ↔ MQTT lifecycle ─────────────────────────────────────── */

    private void on_xmpp_connection_state_changed(Account account,
                                                  ConnectionManager.ConnectionState state) {
        string jid = account.bare_jid.to_string();

        if (state == ConnectionManager.ConnectionState.CONNECTED) {
            if (mode_standalone) {
                /* Standalone: connect once (first account triggers it) */
                if (standalone_client == null && !standalone_connecting) {
                    standalone_connecting = true;
                    start_standalone.begin((obj, res) => {
                        start_standalone.end(res);
                        standalone_connecting = false;
                    });
                }
            } else if (mode_per_account) {
                /* Per-account: connect MQTT for this specific account */
                if (!account_clients.has_key(jid) &&
                    !connecting_accounts.contains(jid)) {
                    connecting_accounts.add(jid);
                    start_per_account.begin(account, (obj, res) => {
                        start_per_account.end(res);
                        connecting_accounts.remove(jid);
                    });
                }
            }
        } else if (state == ConnectionManager.ConnectionState.DISCONNECTED) {
            if (mode_per_account) {
                /* Per-account: disconnect MQTT when XMPP goes offline */
                if (account_clients.has_key(jid)) {
                    message("MQTT: Account %s offline — disconnecting MQTT", jid);
                    account_clients[jid].disconnect_sync();
                    account_clients.unset(jid);
                }
            }
            /* Standalone mode: keep MQTT connected regardless */
        }
    }

    /* ── Standalone connect ────────────────────────────────────────── */

    private async void start_standalone() {
        message("MQTT: Connecting standalone to %s:%d…", cfg_host, cfg_port);

        standalone_client = create_client("standalone");

        bool ok = yield standalone_client.connect_async(
            cfg_host, cfg_port, cfg_tls, cfg_user, cfg_pass);

        if (!ok) {
            warning("MQTT: Standalone connect failed (host=%s port=%d)",
                    cfg_host, cfg_port);
            standalone_client = null;
        }
    }

    /* ── Per-account connect ───────────────────────────────────────── */

    private async void start_per_account(Account account) {
        string jid = account.bare_jid.to_string();
        string host = account.domainpart;

        /* For ejabberd, XMPP credentials can be reused as MQTT login */
        string? user = account.bare_jid.to_string();
        string? pass = account.password;

        message("MQTT: Connecting per-account for %s → %s:%d…",
                jid, host, cfg_port);

        var client = create_client(jid);

        bool ok = yield client.connect_async(
            host, cfg_port, cfg_tls, user, pass);

        if (ok) {
            account_clients[jid] = client;
        } else {
            warning("MQTT: Per-account connect failed for %s (host=%s port=%d)",
                    jid, host, cfg_port);
            client.disconnect_sync();
        }
    }

    /* ── Client factory ────────────────────────────────────────────── */

    private MqttClient create_client(string label) {
        var client = new MqttClient();

        client.on_connection_changed.connect((connected) => {
            connection_changed(label, connected);
            if (connected) {
                message("MQTT [%s]: Connected — subscribing to %d topics",
                        label, cfg_topics.length);
                foreach (string topic in cfg_topics) {
                    string t = topic.strip();
                    if (t != "") {
                        client.subscribe(t);
                    }
                }
            }
        });

        client.on_message.connect((topic, payload) => {
            string payload_str = (string) payload;
            message_received(label, topic, payload_str);
        });

        return client;
    }

    /* ── Public API ────────────────────────────────────────────────── */

    /**
     * Connect to an MQTT broker programmatically (standalone mode).
     * If host is null, the domain of the first XMPP account is used.
     */
    public async bool mqtt_connect(string? host = null, int port = 1883,
                                   bool use_tls = false,
                                   string? username = null,
                                   string? password = null) {
        if (standalone_client != null && standalone_client.is_connected) {
            warning("MQTT: Standalone already connected");
            return true;
        }

        string broker_host = host ?? "";
        if (broker_host == "") {
            var accounts = app.stream_interactor.get_accounts();
            if (accounts.size > 0) {
                broker_host = accounts.first().domainpart;
            } else {
                warning("MQTT: No host specified and no XMPP accounts available");
                return false;
            }
        }

        if (standalone_client == null) {
            standalone_client = create_client("standalone");
        }

        return yield standalone_client.connect_async(
            broker_host, port, use_tls, username, password);
    }

    /**
     * Subscribe to an MQTT topic on all active connections.
     */
    public void subscribe(string topic, int qos = 0) {
        bool any = false;

        if (standalone_client != null && standalone_client.is_connected) {
            standalone_client.subscribe(topic, qos);
            any = true;
        }

        foreach (var entry in account_clients.entries) {
            if (entry.value.is_connected) {
                entry.value.subscribe(topic, qos);
                any = true;
            }
        }

        if (!any) {
            warning("MQTT: Cannot subscribe — no active connections");
        }
    }

    /**
     * Publish a UTF-8 string to an MQTT topic.
     * If account_jid is null, publishes on the standalone connection.
     * If account_jid is given, publishes on that account's connection.
     */
    public void publish(string topic, string payload, int qos = 0,
                        bool retain = false, string? account_jid = null) {
        MqttClient? target = null;

        if (account_jid != null && account_clients.has_key(account_jid)) {
            target = account_clients[account_jid];
        } else if (standalone_client != null) {
            target = standalone_client;
        }

        if (target == null || !target.is_connected) {
            warning("MQTT: Cannot publish — no active connection%s",
                    account_jid != null ? " for " + account_jid : "");
            return;
        }

        target.publish_string(topic, payload, qos, retain);
    }

    /**
     * Disconnect all MQTT connections.
     */
    public async void mqtt_disconnect() {
        if (standalone_client != null) {
            yield standalone_client.disconnect_async();
            standalone_client = null;
        }
        foreach (var entry in account_clients.entries) {
            entry.value.disconnect_sync();
        }
        account_clients.clear();
    }

    /**
     * Get the MqttClient for a specific account (or null).
     */
    public MqttClient? get_client_for_account(string bare_jid) {
        return account_clients.has_key(bare_jid) ? account_clients[bare_jid] : null;
    }

    /**
     * Get the standalone MqttClient (or null).
     */
    public MqttClient? get_standalone_client() {
        return standalone_client;
    }

    /* ── Signals ───────────────────────────────────────────────────── */

    /**
     * Emitted when a message is received on a subscribed topic.
     * source = account JID (per-account) or "standalone".
     */
    public signal void message_received(string source, string topic,
                                         string payload);

    /**
     * Emitted when an MQTT connection state changes.
     * source = account JID (per-account) or "standalone".
     */
    public signal void connection_changed(string source, bool connected);
}

}
