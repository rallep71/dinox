using Xmpp;
using Xmpp.Xep;
using Gee;

namespace Xmpp.Test {

/**
 * Spec-based tests for XEP-0448 Encryption for Stateless File Sharing.
 *
 * References:
 *   - XEP-0448 §3: The <encrypted> element wraps inner <sources> with key/iv
 *   - XEP-0447 §3: <file-sharing> structure with <file> and <sources>
 *   - XEP-0448 namespace: urn:xmpp:esfs:0
 *   - XEP-0447 namespace: urn:xmpp:sfs:0
 */
public class Xep0448Test : Gee.TestCase {
    public Xep0448Test() {
        base("Xep0448Test");
        add_test("XEP0448_encryption_element_structure", test_encryption_element_structure);
        add_test("XEP0448_key_iv_base64_preserved", test_key_iv_base64);
    }

    /**
     * XEP-0448 §3: set_sfs_element MUST produce:
     *   <file-sharing xmlns='urn:xmpp:sfs:0'>
     *     <file .../>
     *     <sources xmlns='urn:xmpp:sfs:0'>
     *       <encrypted xmlns='urn:xmpp:esfs:0'>
     *         <key>...</key>
     *         <iv>...</iv>
     *         <sources xmlns='urn:xmpp:sfs:0'>
     *           <url-data .../>
     *         </sources>
     *       </encrypted>
     *     </sources>
     *   </file-sharing>
     */
    public void test_encryption_element_structure() {
        var message = new MessageStanza();
        var metadata = new FileMetadataElement.FileMetadata();
        metadata.name = "secret.txt";
        metadata.size = 1234;
        
        var sources = new ArrayList<StatelessFileSharing.Source>();
        sources.add(new StatelessFileSharing.HttpSource() { url = "https://example.com/secret.txt" });

        var encryption = new StatelessFileSharing.EncryptionData();
        encryption.key = Base64.decode("MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=");
        encryption.iv = Base64.decode("MDEyMzQ1Njc4OTAx");

        StatelessFileSharing.set_sfs_element(message, "share-id-1", metadata, sources, encryption);

        // XEP-0447: Root <file-sharing> in urn:xmpp:sfs:0
        var sfs_node = message.stanza.get_subnode("file-sharing", StatelessFileSharing.NS_URI);
        assert(sfs_node != null);
        
        // XEP-0447: <sources> inside <file-sharing>
        var sources_node = sfs_node.get_subnode("sources", StatelessFileSharing.NS_URI);
        assert(sources_node != null);

        // XEP-0448: <encrypted> inside <sources> with urn:xmpp:esfs:0 namespace
        var enc_node = sources_node.get_subnode("encrypted", StatelessFileSharing.EncryptionData.NS_URI);
        assert(enc_node != null);

        // XEP-0448 §3: <key> and <iv> children MUST be present
        var key_node = enc_node.get_subnode("key", StatelessFileSharing.EncryptionData.NS_URI);
        assert(key_node != null);

        var iv_node = enc_node.get_subnode("iv", StatelessFileSharing.EncryptionData.NS_URI);
        assert(iv_node != null);

        // XEP-0448 §3: Inner <sources> wraps the actual download URLs
        var inner_sources = enc_node.get_subnode("sources", StatelessFileSharing.NS_URI);
        assert(inner_sources != null);
    }

    /**
     * XEP-0448 §3: Key and IV MUST be Base64-encoded in the XML.
     * Verify the exact Base64 values survive serialization.
     */
    public void test_key_iv_base64() {
        string expected_key_b64 = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=";
        string expected_iv_b64 = "MDEyMzQ1Njc4OTAx";

        var message = new MessageStanza();
        var metadata = new FileMetadataElement.FileMetadata();
        metadata.name = "test.bin";
        metadata.size = 42;
        
        var sources = new ArrayList<StatelessFileSharing.Source>();
        sources.add(new StatelessFileSharing.HttpSource() { url = "https://example.com/test.bin" });

        var encryption = new StatelessFileSharing.EncryptionData();
        encryption.key = Base64.decode(expected_key_b64);
        encryption.iv = Base64.decode(expected_iv_b64);

        StatelessFileSharing.set_sfs_element(message, "id-2", metadata, sources, encryption);

        var sfs_node = message.stanza.get_subnode("file-sharing", StatelessFileSharing.NS_URI);
        var sources_node = sfs_node.get_subnode("sources", StatelessFileSharing.NS_URI);
        var enc_node = sources_node.get_subnode("encrypted", StatelessFileSharing.EncryptionData.NS_URI);

        var key_node = enc_node.get_subnode("key", StatelessFileSharing.EncryptionData.NS_URI);
        assert(key_node.get_string_content() == expected_key_b64);

        var iv_node = enc_node.get_subnode("iv", StatelessFileSharing.EncryptionData.NS_URI);
        assert(iv_node.get_string_content() == expected_iv_b64);
    }
}

}
