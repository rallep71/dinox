/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

namespace Xmpp {

    private class SrvTargetInfo {
        public string host { get; set; }
        public uint16 port { get; set; }
        public string service { get; set; }
        public uint16 priority { get; set; }
    }

    public class XmppStreamResult {
        public TlsXmppStream? stream { get; set; }
        public TlsCertificateFlags? tls_errors { get; set; }
        public TlsCertificate? tls_certificate { get; set; }
        public IOError? io_error { get; set; }
    }

    public async XmppStreamResult establish_stream(Jid bare_jid, Gee.List<XmppStreamModule> modules, string? log_options, owned TlsXmppStream.OnInvalidCert on_invalid_cert, string? custom_host = null, uint16 custom_port = 0, string proxy_type = "none", string? proxy_host = null, uint16 proxy_port = 0) {
        Jid remote = bare_jid.domain_jid;
        TlsXmppStream.OnInvalidCertWrapper on_invalid_cert_wrapper = new TlsXmppStream.OnInvalidCertWrapper((owned)on_invalid_cert);

        //Lookup xmpp-client and xmpps-client SRV records, or use custom host/port if provided
        GLib.List<SrvTargetInfo>? targets = new GLib.List<SrvTargetInfo>();
        
        if (custom_host != null && custom_host.length > 0 && custom_port > 0) {
            // Use custom host and port, skip SRV lookup
            debug("Using custom connection: %s:%u", custom_host, custom_port);
            targets.append(new SrvTargetInfo() { host=custom_host, port=custom_port, service="xmpp-client", priority=0});
        } else {
            // Standard SRV lookup
            GLibFixes.Resolver resolver = GLibFixes.Resolver.get_default();
            try {
                GLib.List<SrvTarget> xmpp_services = yield resolver.lookup_service_async("xmpp-client", "tcp", remote.to_string(), null);
                foreach (SrvTarget service in xmpp_services) {
                    targets.append(new SrvTargetInfo() { host=service.get_hostname(), port=service.get_port(), service="xmpp-client", priority=service.get_priority()});
                }
            } catch (Error e) {
                debug("Got no xmpp-client DNS records for %s: %s", remote.to_string(), e.message);
            }
            try {
                GLib.List<SrvTarget> xmpp_services = yield resolver.lookup_service_async("xmpps-client", "tcp", remote.to_string(), null);
                foreach (SrvTarget service in xmpp_services) {
                    targets.append(new SrvTargetInfo() { host=service.get_hostname(), port=service.get_port(), service="xmpps-client", priority=service.get_priority()});
                }
            } catch (Error e) {
                debug("Got no xmpps-client DNS records for %s: %s", remote.to_string(), e.message);
            }

            targets.sort((a, b) => {
                return a.priority - b.priority;
            });

            // Add fallback connection
            bool should_add_fallback = true;
            foreach (SrvTargetInfo target in targets) {
                if (target.service == "xmpp-client" && target.port == 5222 && target.host == remote.to_string()) {
                    should_add_fallback = false;
                }
            }
            if (should_add_fallback) {
                targets.append(new SrvTargetInfo() { host=remote.to_string(), port=5222, service="xmpp-client", priority=uint16.MAX});
            }
        }

        // Try all connection options from lowest to highest priority
        TlsXmppStream? stream = null;
        TlsCertificateFlags? tls_errors = null;
        TlsCertificate? tls_certificate = null;
        IOError? io_error = null;
        uint connection_timeout_id = 0;
        foreach (SrvTargetInfo target in targets) {
            try {
                if (target.service == "xmpp-client") {
                    stream = new StartTlsXmppStream(remote, target.host, target.port, on_invalid_cert_wrapper, proxy_type, proxy_host, proxy_port);
                } else {
                    stream = new DirectTlsXmppStream(remote, target.host, target.port, on_invalid_cert_wrapper, proxy_type, proxy_host, proxy_port);
                }
                stream.log = new XmppLog(bare_jid.to_string(), log_options);

                foreach (XmppStreamModule module in modules) {
                    stream.add_module(module);
                }

                connection_timeout_id = Timeout.add_seconds(60, () => {
                    warning("Connection attempt timed out");
                    stream.disconnect.begin();
                    connection_timeout_id = 0;
                    return Source.REMOVE;
                });

                yield stream.connect();

                if (connection_timeout_id != 0) {
                    Source.remove(connection_timeout_id);
                    connection_timeout_id = 0;
                }

                return new XmppStreamResult() { stream=stream };
            } catch (IOError e) {
                warning("Could not establish XMPP session with %s:%i: %s", target.host, target.port, e.message);

                if (stream != null) {
                    if (connection_timeout_id != 0) {
                        Source.remove(connection_timeout_id);
                        connection_timeout_id = 0;
                    }
                    if (stream.errors != null) {
                        tls_errors = stream.errors;
                        tls_certificate = stream.peer_certificate;
                    }
                    io_error = e;
                    stream.detach_modules();
                }
            }
        }

        return new XmppStreamResult() { io_error=io_error, tls_errors=tls_errors, tls_certificate=tls_certificate };
    }
}
