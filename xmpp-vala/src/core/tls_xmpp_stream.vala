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
