public abstract class Xmpp.TlsXmppStream : IoXmppStream {

    public TlsCertificateFlags? errors;
    public TlsCertificate? peer_certificate;

    public delegate bool OnInvalidCert(GLib.TlsCertificate peer_cert, GLib.TlsCertificateFlags errors);
    public class OnInvalidCertWrapper {
        public OnInvalidCert func;
        public OnInvalidCertWrapper(owned OnInvalidCert func) {
            this.func = (owned) func;
        }
    }

    protected TlsXmppStream(Jid remote_name) {
        base(remote_name);
    }

    /**
     * Get the TLS peer certificate from the active connection.
     * Works for both successful (CA-signed) and pinned connections.
     */
    public TlsCertificate? get_tls_peer_certificate() {
        // First check if we stored a cert from on_invalid_certificate
        if (peer_certificate != null) return peer_certificate;
        // Otherwise get it from the live TLS connection
        IOStream? io_stream = get_stream();
        if (io_stream != null && io_stream is TlsConnection) {
            return ((TlsConnection) io_stream).peer_certificate;
        }
        return null;
    }

#if GLIB_2_66
    /**
     * Get TLS channel binding data for SCRAM-*-PLUS authentication.
     * Returns null if channel binding is not available.
     *
     * Preference: tls-exporter (RFC 9266, GLib 2.74+) > tls-server-end-point (RFC 5929)
     * tls-unique is NOT supported because it is broken with TLS 1.3.
     */
    public uint8[]? get_channel_binding_data(out string? cb_type) {
        cb_type = null;
        IOStream? io_stream = get_stream();
        if (io_stream == null || !(io_stream is TlsConnection)) return null;
        TlsConnection tls_conn = (TlsConnection) io_stream;

#if GLIB_2_74
        // Prefer tls-exporter (RFC 9266) - works with TLS 1.2 and TLS 1.3
        try {
            var data = new ByteArray();
            if (GLibFixes.tls_get_channel_binding(tls_conn, TlsChannelBindingType.EXPORTER, data)) {
                cb_type = "tls-exporter";
                uint8[] result = new uint8[data.len];
                for (uint i = 0; i < data.len; i++) result[i] = data.data[i];
                return result;
            }
        } catch (Error e) {
            // tls-exporter not available, try tls-server-end-point
        }
#endif

        // Fallback: tls-server-end-point (RFC 5929) - hash of server certificate
        try {
            var data = new ByteArray();
            if (GLibFixes.tls_get_channel_binding(tls_conn, TlsChannelBindingType.SERVER_END_POINT, data)) {
                cb_type = "tls-server-end-point";
                uint8[] result = new uint8[data.len];
                for (uint i = 0; i < data.len; i++) result[i] = data.data[i];
                return result;
            }
        } catch (Error e) {
            warning("Channel binding (tls-server-end-point) failed: %s", e.message);
        }
        return null;
    }
#endif

    protected bool on_invalid_certificate(TlsCertificate peer_cert, TlsCertificateFlags errors) {
        this.errors = errors;
        this.peer_certificate = peer_cert;

        string error_str = "";
        foreach (var f in new TlsCertificateFlags[]{TlsCertificateFlags.UNKNOWN_CA, TlsCertificateFlags.BAD_IDENTITY,
            TlsCertificateFlags.NOT_ACTIVATED, TlsCertificateFlags.EXPIRED, TlsCertificateFlags.REVOKED,
            TlsCertificateFlags.INSECURE, TlsCertificateFlags.GENERIC_ERROR, TlsCertificateFlags.VALIDATE_ALL}) {
            if (f in errors) {
                error_str += @"$(f), ";
            }
        }
        warning(@"[%p, %s] Tls Certificate Errors: %s", this, this.remote_name.to_string(), error_str);
        return false;
    }
}
