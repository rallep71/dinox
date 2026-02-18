using Gee;
using Xmpp;

namespace Xmpp.Xep.StatelessFileSharing {

    public const string NS_URI = "urn:xmpp:sfs:0";

    public static Gee.List<FileShare>? get_file_shares(MessageStanza message) {
        var ret = new ArrayList<FileShare>();
        foreach (StanzaNode file_sharing_node in message.stanza.get_subnodes("file-sharing", NS_URI)) {
            var metadata = Xep.FileMetadataElement.get_file_metadata(file_sharing_node);
            if (metadata == null) continue;

            var sources_node = file_sharing_node.get_subnode("sources", NS_URI);

            ret.add(new FileShare() {
                id = file_sharing_node.get_attribute("id", NS_URI),
                metadata = Xep.FileMetadataElement.get_file_metadata(file_sharing_node),
                sources = sources_node != null ? get_sources(sources_node) : null
            });
        }

        if (ret.size == 0) return null;

        return ret;
    }

    public static Gee.List<SourceAttachment>? get_source_attachments(MessageStanza message) {
        Gee.List<StanzaNode> sources_nodes = message.stanza.get_subnodes("sources", NS_URI);
        if (sources_nodes.is_empty) return null;

        string? attach_to_id = MessageAttaching.get_attach_to(message.stanza);
        if (attach_to_id == null) return null;

        var ret = new ArrayList<SourceAttachment>();

        foreach (StanzaNode sources_node in sources_nodes) {
            ret.add(new SourceAttachment() {
                to_message_id = attach_to_id,
                to_file_transfer_id = sources_node.get_attribute("id", NS_URI),
                sources = get_sources(sources_node)
            });
        }
        return ret;
    }

    public static bool is_sfs_fallback_message(MessageStanza message) {
        Gee.List<FallbackIndication.Fallback> fallbacks = Xep.FallbackIndication.get_fallbacks(message);
        foreach (var fallback in fallbacks) {
            if (fallback.ns_uri == StatelessFileSharing.NS_URI && fallback.locations.any_match((it) => it.is_whole)) {
                return true;
            }
        }
        return false;
    }

    // Parses <sources> node for both plain HTTP and ESFS encrypted sources (XEP-0448)
    private static Gee.List<Source>? get_sources(StanzaNode sources_node) {
        var sources = new Gee.ArrayList<Source>();

        // Check for direct <url-data> (unencrypted)
        string? url = HttpSchemeForUrlData.get_url(sources_node);
        if (url != null) {
            sources.add(new HttpSource() { url=url });
        }

        // Check for ESFS encrypted sources (XEP-0448)
        StanzaNode? encrypted_node = sources_node.get_subnode("encrypted", EsfsHttpSource.NS_URI);
        if (encrypted_node != null) {
            string? cipher = encrypted_node.get_attribute("cipher");
            string? key_str = null;
            string? iv_str = null;

            StanzaNode? key_node = encrypted_node.get_subnode("key", EsfsHttpSource.NS_URI);
            if (key_node != null) key_str = key_node.get_string_content();

            StanzaNode? iv_node = encrypted_node.get_subnode("iv", EsfsHttpSource.NS_URI);
            if (iv_node != null) iv_str = iv_node.get_string_content();

            // Get inner <sources> containing the actual download URL
            StanzaNode? inner_sources_node = encrypted_node.get_subnode("sources", NS_URI);
            if (inner_sources_node != null) {
                string? inner_url = HttpSchemeForUrlData.get_url(inner_sources_node);
                if (inner_url != null && key_str != null && iv_str != null) {
                    var esfs = new EsfsHttpSource();
                    esfs.url = inner_url;
                    esfs.key = Base64.decode(key_str.strip());
                    esfs.iv = Base64.decode(iv_str.strip());
                    esfs.cipher_uri = cipher ?? "";
                    sources.add(esfs);
                }
            }
        }

        if (sources.is_empty) return null;
        return sources;
    }

    public static void set_sfs_element(MessageStanza message, string? file_sharing_id, FileMetadataElement.FileMetadata metadata, Gee.List<Xep.StatelessFileSharing.Source>? sources, EncryptionData? encryption = null) {
        var file_sharing_node = new StanzaNode.build("file-sharing", NS_URI).add_self_xmlns()
                .put_node(metadata.to_stanza_node());
        if (file_sharing_id != null) {
            file_sharing_node.put_attribute("id", file_sharing_id, NS_URI);
        }
        if (sources != null && !sources.is_empty) {
            if (encryption != null) {
                // XEP-0448: Wrap sources inside <encrypted> inside <sources>
                var outer_sources = new StanzaNode.build("sources", NS_URI);
                var encrypted_node = new StanzaNode.build("encrypted", EncryptionData.NS_URI).add_self_xmlns();
                if (encryption.cipher_uri != null && encryption.cipher_uri != "") {
                    encrypted_node.put_attribute("cipher", encryption.cipher_uri);
                }
                var key_node = new StanzaNode.build("key", EncryptionData.NS_URI);
                key_node.put_node(new StanzaNode.text(Base64.encode(encryption.key)));
                encrypted_node.put_node(key_node);
                var iv_node = new StanzaNode.build("iv", EncryptionData.NS_URI);
                iv_node.put_node(new StanzaNode.text(Base64.encode(encryption.iv)));
                encrypted_node.put_node(iv_node);
                // Inner <sources> with the actual URL(s)
                var inner_sources = new StanzaNode.build("sources", NS_URI).add_self_xmlns();
                foreach (var source in sources) {
                    inner_sources.put_node(source.to_stanza_node());
                }
                encrypted_node.put_node(inner_sources);
                outer_sources.put_node(encrypted_node);
                file_sharing_node.put_node(outer_sources);
            } else {
                file_sharing_node.put_node(create_sources_node(file_sharing_id, sources));
            }
        }
        message.stanza.put_node(file_sharing_node);
    }

    public class EncryptionData : Object {
        public const string NS_URI = "urn:xmpp:esfs:0";
        public uint8[] key;
        public uint8[] iv;
        public string? cipher_uri;
    }

    public static void set_sfs_attachment(MessageStanza message, string attach_to_id, string attach_to_file_id, Gee.List<Xep.StatelessFileSharing.Source> sources) {
        message.stanza.put_node(MessageAttaching.to_stanza_node(attach_to_id));
        message.stanza.put_node(create_sources_node(attach_to_file_id, sources).add_self_xmlns());
    }

    private static StanzaNode create_sources_node(string file_sharing_id, Gee.List<Xep.StatelessFileSharing.Source> sources) {
        StanzaNode sources_node = new StanzaNode.build("sources", NS_URI)
                .put_attribute("id", file_sharing_id, NS_URI);
        foreach (var source in sources) {
            sources_node.put_node(source.to_stanza_node());
        }
        return sources_node;
    }

    public class FileShare : Object {
        public string? id { get; set; }
        public Xep.FileMetadataElement.FileMetadata metadata { get; set; }
        public Gee.List<Source>? sources { get; set; }
    }

    public class SourceAttachment : Object {
        public string to_message_id { get; set; }
        public string? to_file_transfer_id { get; set; }
        public Gee.List<Source>? sources { get; set; }
    }

    public interface Source: Object {
        public abstract string type();
        public abstract StanzaNode to_stanza_node();
        public abstract bool equals(Source source);

        public static bool equals_func(Source s1, Source s2) {
            return s1.equals(s2);
        }
    }

    public class HttpSource : Object, Source {
        public string url { get; set; }

        public string type() {
            return "http";
        }

        public StanzaNode to_stanza_node() {
            return HttpSchemeForUrlData.to_stanza_node(url);
        }

        public bool equals(Source source) {
            HttpSource? http_source = source as HttpSource;
            if (http_source == null) return false;
            return http_source.url == this.url;
        }
    }

    /**
     * ESFS (XEP-0448) encrypted HTTP source.
     * Carries the download URL plus encryption key/iv/cipher for file decryption.
     */
    public class EsfsHttpSource : Object, Source {
        public const string NS_URI = "urn:xmpp:esfs:0";
        public string url { get; set; }
        // uint8[] cannot be a GObject property; use plain fields
        public uint8[] key;
        public uint8[] iv;
        public string cipher_uri { get; set; default = ""; }

        public string type() {
            return "esfs";
        }

        public StanzaNode to_stanza_node() {
            return HttpSchemeForUrlData.to_stanza_node(url);
        }

        public bool equals(Source source) {
            EsfsHttpSource? other = source as EsfsHttpSource;
            if (other == null) return false;
            return other.url == this.url;
        }
    }
}
