using Gee;
using Omemo;
using Xmpp;

namespace Dino.Plugins.Omemo {

/**
 * OMEMO 2 bundle parser (XEP-0384 v0.8+).
 *
 * Bundle XML format:
 * <bundle xmlns='urn:xmpp:omemo:2'>
 *   <spk id='1'>base64_signed_pre_key (32 bytes bare)</spk>
 *   <spks>base64_signature (64 bytes)</spks>
 *   <ik>base64_identity_key (32 bytes bare)</ik>
 *   <prekeys>
 *     <pk id='1'>base64_pre_key (32 bytes bare)</pk>
 *   </prekeys>
 * </bundle>
 *
 * Key difference from legacy: bare X25519 keys (32 bytes) instead of
 * DJB-serialized (33 bytes with 0x05 type prefix).
 */
public class Bundle2 {
    public StanzaNode? node;

    private const string NS_V2 = Xmpp.Xep.Omemo.NS_URI_V2;

    public Bundle2(StanzaNode? node) {
        this.node = node;
        Plugin.ensure_context();
    }

    public int32 signed_pre_key_id { get {
        if (node == null) return -1;
        StanzaNode? spk_node = ((!)node).get_subnode("spk", NS_V2);
        if (spk_node == null) return -1;
        string? id = spk_node.get_attribute("id");
        if (id == null) return -1;
        return int.parse((!)id);
    }}

    /**
     * Get signed pre-key (bare 32-byte X25519 Montgomery key).
     */
    public ECPublicKey? signed_pre_key { owned get {
        if (node == null) return null;
        StanzaNode? spk_node = ((!)node).get_subnode("spk", NS_V2);
        if (spk_node == null) return null;
        string? key = spk_node.get_string_content();
        if (key == null) return null;
        try {
            return Plugin.get_context().decode_public_key_mont(Base64.decode((!)key));
        } catch (Error e) {
            warning("Bundle2: Failed to decode signed pre-key: %s", e.message);
            return null;
        }
    }}

    /**
     * Get signed pre-key signature (XEdDSA signature, 64 bytes).
     */
    public uint8[]? signed_pre_key_signature { owned get {
        if (node == null) return null;
        StanzaNode? spks_node = ((!)node).get_subnode("spks", NS_V2);
        if (spks_node == null) return null;
        string? sig = spks_node.get_string_content();
        if (sig == null) return null;
        return Base64.decode((!)sig);
    }}

    /**
     * Get identity key (bare 32-byte Ed25519 key).
     * OMEMO 2 bundles carry IK as Ed25519 (ec_public_key_get_ed()),
     * NOT Montgomery. curve_decode_point with 32 bytes -> curve_decode_point_ed
     * -> stores ed_data (for sig verify) + converts to Montgomery in data (for DH).
     */
    public ECPublicKey? identity_key { owned get {
        if (node == null) return null;
        StanzaNode? ik_node = ((!)node).get_subnode("ik", NS_V2);
        if (ik_node == null) return null;
        string? key = ik_node.get_string_content();
        if (key == null) return null;
        try {
            return Plugin.get_context().decode_public_key(Base64.decode((!)key));
        } catch (Error e) {
            warning("Bundle2: Failed to decode identity key: %s", e.message);
            return null;
        }
    }}

    /**
     * Get pre-keys list.
     */
    public ArrayList<PreKey2> pre_keys { owned get {
        ArrayList<PreKey2> list = new ArrayList<PreKey2>();
        if (node == null) return list;
        StanzaNode? prekeys_node = ((!)node).get_subnode("prekeys", NS_V2);
        if (prekeys_node == null) return list;
        foreach (StanzaNode pk_node in prekeys_node.get_subnodes("pk", NS_V2)) {
            if (pk_node.get_attribute("id") != null) {
                list.add(new PreKey2(pk_node));
            }
        }
        return list;
    }}

    public class PreKey2 {
        private StanzaNode node;

        public PreKey2(StanzaNode node) {
            this.node = node;
        }

        public int32 key_id { get {
            return int.parse(node.get_attribute("id") ?? "-1");
        }}

        public ECPublicKey? key { owned get {
            string? key_str = node.get_string_content();
            if (key_str == null) return null;
            try {
                return Plugin.get_context().decode_public_key_mont(Base64.decode((!)key_str));
            } catch (Error e) {
                warning("Bundle2.PreKey2: Failed to decode pre-key: %s", e.message);
                return null;
            }
        }}
    }
}

}
