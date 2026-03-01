/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;

using Xmpp;
using Dino.Entities;

namespace Dino {

public class ConnectionManager : Object {

    public signal void stream_opened(Account account, XmppStream stream);
    public signal void stream_attached_modules(Account account, XmppStream stream);
    public signal void connection_state_changed(Account account, ConnectionState state);
    public signal void connection_error(Account account, ConnectionError error);
    public signal void certificate_validation_required(
        Account account,
        TlsCertificate peer_cert,
        TlsCertificateFlags errors
    );

    public enum ConnectionState {
        CONNECTED,
        CONNECTING,
        DISCONNECTED
    }

    private HashMap<Account, Connection> connections = new HashMap<Account, Connection>(Account.hash_func, Account.equals_func);
    private HashMap<Account, ConnectionError> connection_errors = new HashMap<Account, ConnectionError>(Account.hash_func, Account.equals_func);

    private HashMap<Account, bool> connection_ongoing = new HashMap<Account, bool>(Account.hash_func, Account.equals_func);
    private HashMap<Account, bool> connection_directly_retry = new HashMap<Account, bool>(Account.hash_func, Account.equals_func);

    private NetworkMonitor? network_monitor;
    private Login1Manager? login1;
    private ModuleManager module_manager;
    public string? log_options;
    private Database? db;

    public class ConnectionError {

        public enum Source {
            CONNECTION,
            SASL,
            TLS,
            STREAM_ERROR
        }

        public enum Reconnect {
            NOW,
            LATER,
            NEVER
        }

        public Source source;
        public string? identifier;
        public Reconnect reconnect_recomendation { get; set; default=Reconnect.NOW; }
        
        // TLS certificate information for certificate pinning
        public TlsCertificate? tls_certificate { get; set; }
        public TlsCertificateFlags tls_flags { get; set; }
        public string? tls_domain { get; set; }

        public ConnectionError(Source source, string? identifier) {
            this.source = source;
            this.identifier = identifier;
        }
    }

    private class Connection {
        public string uuid { get; set; }
        public XmppStream? stream { get; set; }
        public ConnectionState connection_state { get; set; default = ConnectionState.DISCONNECTED; }
        public DateTime? established { get; set; }
        public DateTime? last_activity { get; set; }

        public Connection() {
            reset();
        }

        public void reset() {
            if (stream != null) {
                stream.detach_modules();

                stream.disconnect.begin();
            }
            stream = null;
            established = last_activity = null;
            uuid = Xmpp.random_uuid();
        }

        public void make_offline() {
            Xmpp.Presence.Stanza presence = new Xmpp.Presence.Stanza();
            presence.type_ = Xmpp.Presence.Stanza.TYPE_UNAVAILABLE;
            if (stream != null) {
                stream.get_module<Presence.Module>(Presence.Module.IDENTITY).send_presence(stream, presence);
            }
        }

        public async void disconnect_account() {
            make_offline();

            if (stream != null) {
                try {
                    yield stream.disconnect();
                } catch (Error e) {
                    debug("Error disconnecting stream: %s", e.message);
                }
            }
        }
    }

    public ConnectionManager(ModuleManager module_manager, Database? db = null) {
        this.module_manager = module_manager;
        this.db = db;
        network_monitor = GLib.NetworkMonitor.get_default();
        if (network_monitor != null) {
            network_monitor.network_changed.connect(on_network_changed);
            network_monitor.notify["connectivity"].connect(on_network_changed);
        }

        get_login1.begin((_, res) => {
            login1 = get_login1.end(res);
            if (login1 != null) {
                login1.PrepareForSleep.connect(on_prepare_for_sleep);
            }
        });

        Timeout.add_seconds(60, () => {
            foreach (Account account in connections.keys) {
                if (connections[account].last_activity == null ||
                        connections[account].last_activity.compare(new DateTime.now_utc().add_minutes(-1)) < 0) {
                    check_reconnect(account);
                }
            }
            return true;
        });
    }

    public XmppStream? get_stream(Account account) {
        if (get_state(account) == ConnectionState.CONNECTED) {
            return connections[account].stream;
        }
        return null;
    }

    public ConnectionState get_state(Account account) {
        if (connections.has_key(account)){
            return connections[account].connection_state;
        }
        return ConnectionState.DISCONNECTED;
    }

    public ConnectionError? get_error(Account account) {
        if (connection_errors.has_key(account)) {
            return connection_errors[account];
        }
        return null;
    }

    /**
     * Get the TLS peer certificate for a connected account.
     * Returns the live certificate from the active TLS connection.
     */
    public TlsCertificate? get_peer_certificate(Account account) {
        if (!connections.has_key(account)) return null;
        var stream = connections[account].stream;
        if (stream == null) return null;
        if (stream is Xmpp.TlsXmppStream) {
            return ((Xmpp.TlsXmppStream) stream).get_tls_peer_certificate();
        }
        return null;
    }

    public Collection<Account> get_managed_accounts() {
        return connections.keys;
    }

    public void connect_account(Account account) {
        if (!connections.has_key(account)) {
            connections[account] = new Connection();
            connection_ongoing[account] = false;
            connection_directly_retry[account] = false;

            connect_stream.begin(account);
        } else {
            check_reconnect(account);
        }
    }

    public void make_offline_all() {
        foreach (Account account in connections.keys) {
            make_offline(account);
        }
    }

    private void make_offline(Account account) {
        connections[account].make_offline();
        change_connection_state(account, ConnectionState.DISCONNECTED);
    }

    public async void disconnect_account(Account account) {
        if (connections.has_key(account)) {
            make_offline(account);
            connections[account].disconnect_account.begin();
            connections.unset(account);
        }
    }

    /**
     * Close all XMPP connections without removing account state.
     * Used during application shutdown to cleanly close sockets without
     * triggering account_removed (which would wipe OMEMO identity data).
     */
    public void disconnect_all() {
        foreach (Account account in connections.keys) {
            make_offline(account);
            connections[account].disconnect_account.begin();
        }
        connections.clear();
    }

    private async void connect_stream(Account account) {
        if (!connections.has_key(account)) return;

        debug("[%s] (Maybe) Establishing a new connection", account.bare_jid.to_string());

        connection_errors.unset(account);

        XmppStreamResult stream_result;

        if (connection_ongoing[account]) {
            debug("[%s] Connection attempt already in progress. Directly retry if it fails.", account.bare_jid.to_string());
            connection_directly_retry[account] = true;
            return;
        } else if (connections[account].stream != null) {
            debug("[%s] Cancelling connecting because there is already a stream", account.bare_jid.to_string());
            return;
        } else {
            connection_ongoing[account] = true;
            connection_directly_retry[account] = false;

            change_connection_state(account, ConnectionState.CONNECTING);
            
            // Pass custom host/port if configured
            uint16 custom_port = (account.custom_port > 0 && account.custom_port <= 65535) ? (uint16) account.custom_port : 0;
            uint16 proxy_port = (account.proxy_port > 0 && account.proxy_port <= 65535) ? (uint16) account.proxy_port : 0;
            stream_result = yield Xmpp.establish_stream(account.bare_jid, module_manager.get_modules(account), log_options,
                    (peer_cert, errors) => { return on_invalid_certificate_for_account(account, peer_cert, errors); },
                    account.custom_host, custom_port,
                    account.proxy_type, account.proxy_host, proxy_port
            );

            if (!connections.has_key(account) || connections[account] == null) {
                debug("[%s] Connection object gone while connecting, discarding stream", account.bare_jid.to_string());
                if (stream_result.stream != null) stream_result.stream.disconnect.begin();
                connection_ongoing[account] = false;
                return;
            }

            connections[account].stream = stream_result.stream;

            connection_ongoing[account] = false;
        }

        if (stream_result.stream == null) {
            if (stream_result.tls_errors != null) {
                var error = new ConnectionError(ConnectionError.Source.TLS, null) { 
                    reconnect_recomendation = ConnectionError.Reconnect.NEVER,
                    tls_flags = stream_result.tls_errors,
                    tls_certificate = stream_result.tls_certificate,
                    tls_domain = account.domainpart
                };
                set_connection_error(account, error);
                return;
            }

            debug("[%s] Could not connect", account.bare_jid.to_string());

            change_connection_state(account, ConnectionState.DISCONNECTED);

            check_reconnect(account, connection_directly_retry[account]);

            return;
        }

        XmppStream stream = stream_result.stream;

        debug("[%s] New connection: %p", account.full_jid.to_string(), stream);

        connections[account].established = new DateTime.now_utc();
        stream.attached_modules.connect((stream) => {
            stream_attached_modules(account, stream);
            change_connection_state(account, ConnectionState.CONNECTED);

//            stream.get_module<Xep.Muji.Module>(Xep.Muji.Module.IDENTITY).join_call(stream, new Jid("test@muc.poez.io"), true);
        });
        stream.get_module<Sasl.Module>(Sasl.Module.IDENTITY).received_auth_failure.connect((stream, node) => {
            set_connection_error(account, new ConnectionError(ConnectionError.Source.SASL, null));
        });

        string connection_uuid = connections[account].uuid;
        stream.received_node.connect(() => {
            if (connections[account].uuid == connection_uuid) {
                connections[account].last_activity = new DateTime.now_utc();
            } else {
                warning("Got node for outdated connection");
            }
        });
        stream_opened(account, stream);

        try {
            yield stream.loop();
        } catch (Error e) {
            debug("[%s %p] Connection error: %s", account.bare_jid.to_string(), stream, e.message);

            change_connection_state(account, ConnectionState.DISCONNECTED);
            if (!connections.has_key(account)) return;
            connections[account].reset();

            StreamError.Flag? flag = stream.get_flag(StreamError.Flag.IDENTITY);
            if (flag != null) {
                warning(@"[%s %p] Stream Error: %s", account.bare_jid.to_string(), stream, flag.error_type);
                set_connection_error(account, new ConnectionError(ConnectionError.Source.STREAM_ERROR, flag.error_type));

                if (flag.resource_rejected) {
                    account.set_random_resource();
                    connect_stream.begin(account);
                    return;
                }
            }

            ConnectionError? error = connection_errors[account];
            if (error != null && error.source == ConnectionError.Source.SASL) {
                return;
            }

            check_reconnect(account);
        }
    }

    private void check_reconnects() {
        foreach (Account account in connections.keys) {
            check_reconnect(account);
        }
    }

    private void check_reconnect(Account account, bool directly_reconnect = false) {
        if (!connections.has_key(account)) return;

        bool acked = false;
        DateTime? last_activity_was = connections[account].last_activity;

        if (connections[account].stream == null) {
            Timeout.add_seconds(10, () => {
                if (!connections.has_key(account)) return false;
                if (connections[account].stream != null) return false;
                if (connections[account].last_activity != last_activity_was) return false;

                connect_stream.begin(account);
                return false;
            });
            return;
        }

        XmppStream stream = connections[account].stream;

        stream.get_module<Xep.Ping.Module>(Xep.Ping.Module.IDENTITY).send_ping.begin(stream, account.bare_jid.domain_jid, () => {
            acked = true;
            if (connections[account].stream != stream) return;
            change_connection_state(account, ConnectionState.CONNECTED);
        });

        Timeout.add_seconds(10, () => {
            if (!connections.has_key(account)) return false;
            if (connections[account].stream != stream) return false;
            if (acked) return false;
            if (connections[account].last_activity != last_activity_was) return false;

            // Reconnect. Nothing gets through the stream.
            debug("[%s %p] Ping timeouted. Reconnecting", account.bare_jid.to_string(), stream);
            change_connection_state(account, ConnectionState.DISCONNECTED);

            connections[account].reset();
            connect_stream.begin(account);
            return false;
        });
    }

    private bool network_is_online() {
        /* FIXME: We should also check for connectivity eventually. For more
         * details on why we don't do it for now, see:
         *
         * - https://github.com/dino/dino/pull/236#pullrequestreview-86851793
         * - https://bugzilla.gnome.org/show_bug.cgi?id=792240
         */
        return network_monitor != null && network_monitor.network_available;
    }

    private void on_network_changed() {
        if (network_is_online()) {
            debug("NetworkMonitor: Network reported online");
            check_reconnects();
        } else {
            debug("NetworkMonitor: Network reported offline");
            foreach (Account account in connections.keys) {
                change_connection_state(account, ConnectionState.DISCONNECTED);
            }
        }
    }

    private async void on_prepare_for_sleep(bool suspend) {
        foreach (Account account in connections.keys) {
            change_connection_state(account, ConnectionState.DISCONNECTED);
        }
        if (suspend) {
            debug("Login1: Device suspended");
            foreach (Account account in connections.keys) {
                try {
                    make_offline(account);
                    if (connections[account].stream != null) {
                        yield connections[account].stream.disconnect();
                    }
                } catch (Error e) {
                    debug("Error disconnecting stream %p: %s", connections[account].stream, e.message);
                }
            }
        } else {
            debug("Login1: Device un-suspend");
            check_reconnects();
        }
    }

    private void change_connection_state(Account account, ConnectionState state) {
        if (connections.has_key(account)) {
            connections[account].connection_state = state;
            connection_state_changed(account, state);
        }
    }

    private void set_connection_error(Account account, ConnectionError error) {
        connection_errors[account] = error;
        connection_error(account, error);

        // Auto-trigger certificate dialog for TLS errors with certificate info
        if (error.source == ConnectionError.Source.TLS && error.tls_certificate != null) {
            certificate_validation_required(account, error.tls_certificate, error.tls_flags);
        }
    }

    /**
     * Validates a TLS certificate. Returns true if the certificate should be accepted.
     * This method checks for pinned certificates and special cases like .onion domains.
     */
    public bool on_invalid_certificate_for_account(Account account, TlsCertificate peer_cert, TlsCertificateFlags errors) {
        string domain = account.domainpart;
        
        // .onion domains get special treatment - accept unknown CA
        if (domain.has_suffix(".onion") && errors == TlsCertificateFlags.UNKNOWN_CA) {
            warning("Accepting TLS certificate from unknown CA from .onion address %s", domain);
            return true;
        }

        // Check if certificate is already pinned
        if (db != null) {
            string cert_fp = CertificateManager.get_certificate_fingerprint(peer_cert);
            string? pinned_fp = db.pinned_certificate.get_pinned_fingerprint(domain);

            if (pinned_fp != null && pinned_fp == cert_fp) {
                // Certificate matches pinned fingerprint - accept it
                debug("Certificate for %s matches pinned fingerprint, accepting", domain);
                return true;
            }
        }

        // Certificate not trusted - will trigger connection error with cert info
        // The UI can then show a dialog to pin the certificate
        warning("TLS certificate for %s not trusted (flags: %s)", domain, errors.to_string());
        return false;
    }

    public static bool on_invalid_certificate(string domain, TlsCertificate peer_cert, TlsCertificateFlags errors, Database? db = null) {
        if (domain.has_suffix(".onion") && errors == TlsCertificateFlags.UNKNOWN_CA) {
            // It's barely possible for .onion servers to provide a non-self-signed cert.
            // But that's fine because encryption is provided independently though TOR.
            warning("Accepting TLS certificate from unknown CA from .onion address %s", domain);
            return true;
        }

        // Check if certificate is pinned (e.g. self-signed certs accepted by user for XMPP connection)
        // This ensures HTTP file uploads/downloads work with the same pinned certs
        if (db != null) {
            string cert_fp = CertificateManager.get_certificate_fingerprint(peer_cert);
            string? pinned_fp = db.pinned_certificate.get_pinned_fingerprint(domain);

            if (pinned_fp != null && pinned_fp == cert_fp) {
                debug("HTTP certificate for %s matches pinned fingerprint, accepting", domain);
                return true;
            }
        }

        return false;
    }

    /**
     * Pin a certificate for the given domain. Call this when user accepts an untrusted certificate.
     */
    public void pin_certificate(string domain, TlsCertificate cert, TlsCertificateFlags flags) {
        if (db == null) return;
        CertificateManager.pin_to_db(db, domain, cert, flags);
    }

    /**
     * Remove a pinned certificate for the given domain.
     */
    public void unpin_certificate(string domain) {
        if (db == null) return;
        
        db.pinned_certificate.delete()
            .with(db.pinned_certificate.domain, "=", domain)
            .perform();
        debug("Certificate unpinned for domain %s", domain);
    }

    /**
     * Check if a certificate is pinned for the given domain.
     */
    public bool is_certificate_pinned(string domain) {
        if (db == null) return false;
        return db.pinned_certificate.get_pinned_fingerprint(domain) != null;
    }

    /**
     * Get information about a pinned certificate.
     */
    public CertificateInfo? get_pinned_certificate_info(string domain) {
        if (db == null) return null;
        return CertificateManager.get_pinned_info_from_db(db, domain);
    }
}

}
