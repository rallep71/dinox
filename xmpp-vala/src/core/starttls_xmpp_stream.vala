public class Xmpp.StartTlsXmppStream : TlsXmppStream {

    private const string TLS_NS_URI = "urn:ietf:params:xml:ns:xmpp-tls";

    string host;
    uint16 port;
    TlsXmppStream.OnInvalidCertWrapper on_invalid_cert;
    string proxy_type;
    string? proxy_host;
    uint16 proxy_port;

    public StartTlsXmppStream(Jid remote, string host, uint16 port, TlsXmppStream.OnInvalidCertWrapper on_invalid_cert, string proxy_type = "none", string? proxy_host = null, uint16 proxy_port = 0) {
        base(remote);
        this.host = host;
        this.port = port;
        this.on_invalid_cert = on_invalid_cert;
        this.proxy_type = proxy_type;
        this.proxy_host = proxy_host;
        this.proxy_port = proxy_port;
    }

    public override async void connect() throws IOError {
        try {
            SocketClient client = new SocketClient();
            if (proxy_type != "none") {
                string uri = "";
                if (proxy_type == "tor") {
                    string h = (proxy_host != null && proxy_host != "") ? proxy_host : "127.0.0.1";
                    uint16 p = (proxy_port > 0) ? proxy_port : 9050;
                    // Use socks5:// - GLib Networking should handle remote DNS with SOCKS5
                    uri = "socks5://%s:%u".printf(h, p);
                } else if (proxy_type == "socks5") {
                    if (proxy_host != null && proxy_host != "") {
                        uri = "socks5://%s:%u".printf(proxy_host, proxy_port);
                    }
                }
                
                if (uri != "") {
                    debug("Setting Proxy Resolver to %s", uri);
                    client.set_proxy_resolver(new SimpleProxyResolver(uri, null));
                } else {
                    debug("Proxy URI was empty despite proxy_type being set!");
                }
            } else {
                debug("No proxy configured (proxy_type=none)");
            }

            debug("Connecting to %s:%i (starttls)", host, port);
            IOStream stream = yield client.connect_to_host_async(host, port, cancellable);
            debug("Connection established via SocketClient");
            reset_stream(stream);

            yield setup();

            StanzaNode node = yield read();
            var starttls_node = node.get_subnode("starttls", TLS_NS_URI);
            if (starttls_node == null) {
                warning("%s does not offer starttls", remote_name.to_string());
            }

            yield write_async(new StanzaNode.build("starttls", TLS_NS_URI).add_self_xmlns());

            node = yield read();

            if (node.ns_uri != TLS_NS_URI || node.name != "proceed") {
                throw new IOError.CONNECTION_REFUSED("%s did not proceed with STARTTLS", remote_name.to_string());
            }

            try {
                var identity = new NetworkService("xmpp-client", "tcp", remote_name.to_string());
                var conn = TlsClientConnection.new(get_stream(), identity);
                reset_stream(conn);

                conn.accept_certificate.connect(on_invalid_certificate);
                conn.accept_certificate.connect((cert, flags) => on_invalid_cert.func(cert, flags));
            } catch (Error e) {
                warning("Failed to start TLS: %s", e.message);
            }

            yield setup();

            attach_negotation_modules();
        } catch (IOError e) {
            throw e;
        } catch (Error e) {
            throw new IOError.CONNECTION_REFUSED("Failed connecting to %s:%i (starttls): %s", host, port, e.message);
        }
    }
}
