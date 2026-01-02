using Xmpp;
using Xmpp.Xep;
using Gee;

namespace Xmpp.Test {

public class Xep0448Test : Gee.TestCase {
    public Xep0448Test() {
        base("Xep0448Test");
        add_test("test_encryption_element", test_encryption_element);
    }

    public void test_encryption_element() {
        var message = new MessageStanza();
        var metadata = new FileMetadataElement.FileMetadata();
        metadata.name = "secret.txt";
        metadata.size = 1234;
        
        var sources = new ArrayList<StatelessFileSharing.Source>();
        sources.add(new StatelessFileSharing.HttpSource() { url = "https://example.com/secret.txt" });

        var encryption = new StatelessFileSharing.EncryptionData();
        encryption.key = Base64.decode("MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="); // 32 bytes
        encryption.iv = Base64.decode("MDEyMzQ1Njc4OTAx"); // 12 bytes

        StatelessFileSharing.set_sfs_element(message, "share-id-1", metadata, sources, encryption);

        var sfs_node = message.stanza.get_subnode("file-sharing", StatelessFileSharing.NS_URI);
        assert(sfs_node != null);
        
        var enc_node = sfs_node.get_subnode("encryption", StatelessFileSharing.EncryptionData.NS_URI);
        assert(enc_node != null);

        var key_node = enc_node.get_subnode("key", StatelessFileSharing.EncryptionData.NS_URI);
        assert(key_node != null);
        assert(key_node.get_string_content() == "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=");

        var iv_node = enc_node.get_subnode("iv", StatelessFileSharing.EncryptionData.NS_URI);
        assert(iv_node != null);
        assert(iv_node.get_string_content() == "MDEyMzQ1Njc4OTAx");
    }
}

}
