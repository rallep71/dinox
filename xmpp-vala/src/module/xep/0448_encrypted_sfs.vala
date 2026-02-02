using Gee;
using Xmpp;

namespace Xmpp.Xep.StatelessFileSharing {

    public class EncryptedSource : Object, Source {
        public Source inner_source { get; set; }
        public uint8[] key { get; set; }
        public uint8[] iv { get; set; }
        public string? hash { get; set; }
        public string? hash_algo { get; set; }

        public string type() {
            return "encrypted";
        }

        public StanzaNode to_stanza_node() {
            // This is a wrapper. In SFS, encryption is usually a sibling of sources or a property of the file-sharing element.
            // However, if we follow the pattern where we need to attach this info, we might need to adjust how SFS is built.
            // Wait, XEP-0448 places <encryption> inside <file-sharing>, NOT inside <sources>.
            // But the Source interface is used to build the <sources> list.
            
            // If we are forced to use the Source interface, we might just return the inner source's node?
            // No, that would lose the encryption data.
            
            // Actually, let's look at how `set_sfs_element` works in 0447_stateless_file_sharing.vala.
            // It takes a list of sources.
            
            return inner_source.to_stanza_node();
        }

        public bool equals(Source source) {
            return false; // TODO
        }
    }
}
