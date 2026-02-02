public class Xmpp.DirectTlsXmppStream : TlsXmppStream {

    private const string[] ADVERTISED_PROTOCOLS = {"xmpp-client", null};

    string host;
    uint16 port;
    TlsXmppStream.OnInvalidCertWrapper on_invalid_cert;
    string proxy_type;
    string? proxy_host;
    uint16 proxy_port;

    public DirectTlsXmppStream(Jid remote_name, string host, uint16 port, TlsXmppStream.OnInvalidCertWrapper on_invalid_cert, string proxy_type = "none", string? proxy_host = null, uint16 proxy_port = 0) {
        base(remote_name);
        this.host = host;
        this.port = port;
        this.on_invalid_cert = on_invalid_cert;
        this.proxy_type = proxy_type;
        this.proxy_host = proxy_host;
        this.proxy_port = proxy_port;
    }

    public override async void connect() throws IOError {
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
                debug("Setting Proxy Resolver (DirectTLS) to %s", uri);
                client.set_proxy_resolver(new SimpleProxyResolver(uri, null));
            }
        } else {
            debug("No proxy configured (DirectTLS)");
        }

        try {
            debug("Connecting to %s:%i (tls)", host, port);
            IOStream? io_stream = yield client.connect_to_host_async(host, port, cancellable);
            debug("Connection established (DirectTLS)");
            TlsConnection tls_connection = TlsClientConnection.new(io_stream, new NetworkAddress(remote_name.to_string(), port));
#if GLIB_2_60
            tls_connection.set_advertised_protocols(ADVERTISED_PROTOCOLS);
#endif
            tls_connection.accept_certificate.connect(on_invalid_certificate);
            tls_connection.accept_certificate.connect((cert, flags) => on_invalid_cert.func(cert, flags));
            reset_stream(tls_connection);

            yield setup();

            attach_negotation_modules();
        } catch (IOError e) {
            throw e;
        } catch (Error e) {
            throw new IOError.CONNECTION_REFUSED("Failed connecting to %s:%i (tls): %s", host, port, e.message);
        }
    }
}
