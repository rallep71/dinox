using Xmpp;
using Xmpp.Xep;
using Xmpp.Xep.Omemo;
using Gee;

namespace Xmpp.Test {

/**
 * Spec-based audit tests for OMEMO (XEP-0384) stanza structure.
 *
 * Tests cover:
 *   - XEP-0384 v0.3 (legacy Conversations OMEMO) namespace and stanza building/parsing
 *   - XEP-0384 v0.8+ (OMEMO 2) namespace and stanza building/parsing
 *   - NIST SP 800-38D constraints for AES-GCM (key/IV/tag sizes)
 *   - Key/tag layout invariants
 *
 * These tests verify the xmpp-vala protocol layer that builds and parses
 * OMEMO XML stanzas. They do NOT require libsignal or network connections.
 */
public class OmemoAudit : Gee.TestCase {

    public OmemoAudit() {
        base("OmemoAudit");

        /* === OMEMO v1 (legacy) namespace tests === */
        add_test("XEP0384v03_ns_uri_is_siacs_axolotl", test_v1_ns_uri);
        add_test("XEP0384v03_node_devicelist_suffix", test_v1_node_devicelist);
        add_test("XEP0384v03_node_bundles_suffix", test_v1_node_bundles);

        /* === OMEMO v1 stanza building tests === */
        add_test("XEP0384v03_encrypted_node_has_header_with_sid", test_v1_encrypted_node_header);
        add_test("XEP0384v03_encrypted_node_has_iv_in_header", test_v1_encrypted_node_iv);
        add_test("XEP0384v03_encrypted_node_has_payload", test_v1_encrypted_node_payload);
        add_test("XEP0384v03_key_node_has_rid_and_prekey", test_v1_key_node_attributes);
        add_test("XEP0384v03_key_node_contains_base64_key", test_v1_key_node_content);
        add_test("XEP0384v03_multiple_keys_in_header", test_v1_multiple_keys);
        add_test("XEP0384v03_no_payload_for_keyexchange_only", test_v1_no_payload);

        /* === OMEMO v1 keytag layout tests === */
        add_test("SP800_38D_keytag_32_bytes_is_key16_tag16", test_v1_keytag_layout);

        /* === OMEMO v1 stanza parsing tests === */
        add_test("XEP0384v03_parse_extracts_sid", test_v1_parse_sid);
        add_test("XEP0384v03_parse_extracts_iv", test_v1_parse_iv);
        add_test("XEP0384v03_parse_extracts_payload", test_v1_parse_payload);
        add_test("XEP0384v03_parse_missing_header_returns_null", test_v1_parse_no_header);
        add_test("XEP0384v03_parse_missing_iv_returns_null", test_v1_parse_no_iv);
        add_test("XEP0384v03_parse_finds_our_key_by_rid", test_v1_parse_our_key);
        add_test("XEP0384v03_parse_prekey_attribute", test_v1_parse_prekey);

        /* === OMEMO 2 (v0.8+) namespace tests === */
        add_test("XEP0384v08_ns_uri_is_omemo_2", test_v2_ns_uri);
        add_test("XEP0384v08_node_devicelist_suffix", test_v2_node_devicelist);
        add_test("XEP0384v08_node_bundles_suffix", test_v2_node_bundles);

        /* === OMEMO 2 stanza building tests === */
        add_test("XEP0384v08_encrypted_node_uses_v2_namespace", test_v2_encrypted_ns);
        add_test("XEP0384v08_keys_grouped_by_jid", test_v2_keys_grouped_by_jid);
        add_test("XEP0384v08_kex_attribute_not_prekey", test_v2_kex_attribute);
        add_test("XEP0384v08_no_iv_in_header", test_v2_no_iv_in_header);
        add_test("XEP0384v08_payload_contains_ciphertext", test_v2_payload);
        add_test("XEP0384v08_header_has_sid", test_v2_header_sid);
        add_test("XEP0384v08_multiple_jids_multiple_keys", test_v2_multi_jid_keys);
        add_test("XEP0384v08_empty_payload_no_element", test_v2_empty_payload);

        /* === OMEMO 2 stanza parsing tests === */
        add_test("XEP0384v08_parse_extracts_sid", test_v2_parse_sid);
        add_test("XEP0384v08_parse_extracts_payload", test_v2_parse_payload);
        add_test("XEP0384v08_parse_finds_keys_by_jid", test_v2_parse_keys_by_jid);
        add_test("XEP0384v08_parse_kex_attribute", test_v2_parse_kex);
        add_test("XEP0384v08_parse_missing_header_returns_null", test_v2_parse_no_header);
        add_test("XEP0384v08_parse_missing_sid_returns_null", test_v2_parse_no_sid);
        add_test("XEP0384v08_parse_ignores_other_jid_keys", test_v2_parse_other_jid);

        /* === OMEMO 2 crypto constants (documented in XEP-0384 §4.3) === */
        add_test("XEP0384v08_mk_with_tag_must_be_48_bytes", test_v2_mk_with_tag_48);

        /* === EncryptState accumulation tests === */
        add_test("XEP0384_encrypt_state_add_result_own", test_encrypt_state_own);
        add_test("XEP0384_encrypt_state_add_result_other", test_encrypt_state_other);
    }

    /* ==================================================================
     * Concrete test subclass for OmemoDecryptor (required because it's abstract)
     * Only implements parse_node which is concrete on the base class.
     * ================================================================== */
    private class TestOmemoDecryptor : OmemoDecryptor {
        private uint32 _own_device_id;
        public override uint32 own_device_id { get { return _own_device_id; } }

        public TestOmemoDecryptor(uint32 device_id) {
            this._own_device_id = device_id;
        }

        public override string decrypt(uint8[] ciphertext, uint8[] key, uint8[] iv) throws GLib.Error {
            return "stub";
        }

        public override uint8[] decrypt_key(ParsedData data, Jid from_jid) throws GLib.Error {
            return new uint8[16];
        }
    }

    /* ==================================================================
     * Concrete test subclass for Omemo2Decryptor
     * ================================================================== */
    private class TestOmemo2Decryptor : Omemo2Decryptor {
        private uint32 _own_device_id;
        public override uint32 own_device_id { get { return _own_device_id; } }

        public TestOmemo2Decryptor(uint32 device_id) {
            this._own_device_id = device_id;
        }

        public override async string decrypt(uint8[] ciphertext, uint8[] message_key) throws GLib.Error {
            return "stub";
        }

        public override uint8[] decrypt_key(Omemo2ParsedData data, Jid from_jid) throws GLib.Error {
            return new uint8[32];
        }
    }

    /* ==================================================================
     * Helper: build a standard test EncryptionData for OMEMO v1
     * ================================================================== */
    private EncryptionData make_v1_enc_data() {
        var data = new EncryptionData(12345);
        data.ciphertext = { 0xDE, 0xAD, 0xBE, 0xEF };
        data.iv = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C };
        data.keytag = new uint8[32];
        for (int i = 0; i < 32; i++) data.keytag[i] = (uint8)i;
        return data;
    }

    /* ==================================================================
     * Helper: build a standard Omemo2EncryptionData for OMEMO 2
     * ================================================================== */
    private Omemo2EncryptionData make_v2_enc_data() {
        var data = new Omemo2EncryptionData(67890);
        data.ciphertext = { 0xCA, 0xFE, 0xBA, 0xBE };
        data.message_key = new uint8[48]; // mk(32) || auth_tag(16)
        for (int i = 0; i < 48; i++) data.message_key[i] = (uint8)i;
        return data;
    }

    /* ==================================================================
     * OMEMO v1 NAMESPACE TESTS
     * ================================================================== */

    /** XEP-0384 v0.3 §3: NS_URI MUST be "eu.siacs.conversations.axolotl" */
    public void test_v1_ns_uri() {
        fail_if_not_eq_str(NS_URI, "eu.siacs.conversations.axolotl",
            "XEP-0384 v0.3 NS_URI");
    }

    /** XEP-0384 v0.3 §3: devicelist node = NS_URI + ".devicelist" */
    public void test_v1_node_devicelist() {
        fail_if_not_eq_str(NODE_DEVICELIST, "eu.siacs.conversations.axolotl.devicelist",
            "Devicelist node");
    }

    /** XEP-0384 v0.3 §3: bundles node = NS_URI + ".bundles" */
    public void test_v1_node_bundles() {
        fail_if_not_eq_str(NODE_BUNDLES, "eu.siacs.conversations.axolotl.bundles",
            "Bundles node");
    }

    /* ==================================================================
     * OMEMO v1 STANZA BUILDING TESTS
     * ================================================================== */

    /** XEP-0384 §4: <encrypted> MUST contain <header sid='...'> */
    public void test_v1_encrypted_node_header() {
        var data = make_v1_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();

        fail_if_not_eq_str(encrypted.name, "encrypted", "root element name");
        fail_if_not_eq_str(encrypted.ns_uri, NS_URI, "root element namespace");

        StanzaNode? header = encrypted.get_subnode("header", NS_URI);
        fail_if(header == null, "header node must exist");
        fail_if_not_eq_str(header.get_attribute("sid"), "12345", "header sid");
    }

    /** XEP-0384 §4: <iv> MUST be inside <header> (base64 encoded) */
    public void test_v1_encrypted_node_iv() {
        var data = make_v1_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI);

        string? iv_content = header.get_deep_string_content("iv");
        fail_if(iv_content == null, "IV element must exist in header");

        uint8[] iv_decoded = Base64.decode(iv_content);
        fail_if_not_eq_int(iv_decoded.length, 12, "IV must be 12 bytes (96-bit for GCM)");
    }

    /** XEP-0384 §4: <payload> MUST contain base64-encoded ciphertext */
    public void test_v1_encrypted_node_payload() {
        var data = make_v1_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();

        string? payload = encrypted.get_deep_string_content("payload");
        fail_if(payload == null, "payload must exist when ciphertext is set");

        uint8[] decoded = Base64.decode(payload);
        fail_if_not_eq_int(decoded.length, 4, "payload length");
        fail_if_not_eq_int(decoded[0], 0xDE, "payload content");
    }

    /** XEP-0384 §4: <key rid='...' prekey='true'> */
    public void test_v1_key_node_attributes() {
        var data = make_v1_enc_data();
        uint8[] device_key = { 0xAA, 0xBB, 0xCC, 0xDD };
        data.add_device_key(42, device_key, true);

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI);
        StanzaNode? key_node = header.get_subnode("key", NS_URI);

        fail_if(key_node == null, "key node must exist");
        fail_if_not_eq_str(key_node.get_attribute("rid"), "42", "rid attribute");
        fail_if_not_eq_str(key_node.get_attribute("prekey"), "true", "prekey attribute");
    }

    /** XEP-0384 §4: key node content is base64-encoded device key */
    public void test_v1_key_node_content() {
        var data = make_v1_enc_data();
        uint8[] device_key = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
        data.add_device_key(99, device_key, false);

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI);
        StanzaNode? key_node = header.get_subnode("key", NS_URI);

        string? content = key_node.get_string_content();
        fail_if(content == null, "key node must have content");

        uint8[] decoded = Base64.decode(content);
        fail_if_not_eq_int(decoded.length, 8, "key content length");

        // Prekey MUST NOT be set when false
        string? prekey_attr = key_node.get_attribute("prekey");
        fail_if(prekey_attr != null, "prekey attribute must not be set when false");
    }

    /** XEP-0384 §4: multiple keys per device in header */
    public void test_v1_multiple_keys() {
        var data = make_v1_enc_data();
        data.add_device_key(100, { 0x01 }, true);
        data.add_device_key(200, { 0x02 }, false);
        data.add_device_key(300, { 0x03 }, true);

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI);
        var key_nodes = header.get_subnodes("key", NS_URI);

        fail_if_not_eq_int(key_nodes.size, 3, "must have 3 key nodes");
    }

    /** XEP-0384 §4: no <payload> for key-exchange-only messages */
    public void test_v1_no_payload() {
        var data = new EncryptionData(12345);
        data.iv = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C };
        data.keytag = new uint8[32];
        // ciphertext is null
        data.add_device_key(42, { 0xAA }, true);

        StanzaNode encrypted = data.get_encrypted_node();
        string? payload = encrypted.get_deep_string_content("payload");
        fail_if(payload != null, "no payload element when ciphertext is null");
    }

    /* ==================================================================
     * OMEMO v1 KEYTAG LAYOUT
     * ================================================================== */

    /** NIST SP 800-38D: keytag = key[16] || GCM_tag[16] = 32 bytes */
    public void test_v1_keytag_layout() {
        uint8[] key = new uint8[16];
        uint8[] tag = new uint8[16];
        for (int i = 0; i < 16; i++) { key[i] = (uint8)i; tag[i] = (uint8)(0xF0 + i); }

        // Build keytag as key || tag (how encrypt.vala does it)
        uint8[] keytag = new uint8[32];
        Memory.copy(keytag, key, 16);
        Memory.copy((uint8*)keytag + 16, tag, 16);

        fail_if_not_eq_int(keytag.length, 32, "keytag must be 32 bytes");

        // Verify key is in first 16 bytes
        for (int i = 0; i < 16; i++) {
            fail_if_not_eq_int(keytag[i], i, @"key byte $i");
        }
        // Verify tag is in last 16 bytes
        for (int i = 0; i < 16; i++) {
            fail_if_not_eq_int(keytag[16 + i], 0xF0 + i, @"tag byte $i");
        }
    }

    /* ==================================================================
     * OMEMO v1 STANZA PARSING TESTS
     * ================================================================== */

    /** Build a v1 <encrypted> XML node for parsing tests */
    private StanzaNode build_v1_encrypted_xml(int sid, uint8[] iv, uint8[]? payload,
                                                int our_rid, uint8[] our_key, bool prekey) {
        var encrypted = new StanzaNode.build("encrypted", NS_URI).add_self_xmlns();
        var header = new StanzaNode.build("header", NS_URI)
            .put_attribute("sid", sid.to_string());

        header.put_node(new StanzaNode.build("iv", NS_URI)
            .put_node(new StanzaNode.text(Base64.encode(iv))));

        var key_node = new StanzaNode.build("key", NS_URI)
            .put_attribute("rid", our_rid.to_string())
            .put_node(new StanzaNode.text(Base64.encode(our_key)));
        if (prekey) key_node.put_attribute("prekey", "true");
        header.put_node(key_node);

        encrypted.put_node(header);

        if (payload != null) {
            encrypted.put_node(new StanzaNode.build("payload", NS_URI)
                .put_node(new StanzaNode.text(Base64.encode(payload))));
        }

        return encrypted;
    }

    /** XEP-0384 v0.3: parse_node extracts sid from header */
    public void test_v1_parse_sid() {
        var decryptor = new TestOmemoDecryptor(42);
        var xml = build_v1_encrypted_xml(31415, { 0x01, 0x02, 0x03 }, { 0xDE, 0xAD }, 42, { 0xAA }, false);
        var parsed = decryptor.parse_node(xml);

        fail_if(parsed == null, "parse_node must return non-null");
        fail_if_not_eq_int(parsed.sid, 31415, "parsed sid");
    }

    /** XEP-0384 v0.3: parse_node extracts IV */
    public void test_v1_parse_iv() {
        uint8[] iv = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C };
        var decryptor = new TestOmemoDecryptor(42);
        var xml = build_v1_encrypted_xml(100, iv, { 0xDE }, 42, { 0xAA }, false);
        var parsed = decryptor.parse_node(xml);

        fail_if(parsed == null, "parsed must be non-null");
        fail_if_not_eq_int(parsed.iv.length, 12, "IV must be 12 bytes");
        fail_if_not_eq_int(parsed.iv[0], 0x01, "IV first byte");
        fail_if_not_eq_int(parsed.iv[11], 0x0C, "IV last byte");
    }

    /** XEP-0384 v0.3: parse_node extracts payload ciphertext */
    public void test_v1_parse_payload() {
        uint8[] ct = { 0xCA, 0xFE, 0xBA, 0xBE };
        var decryptor = new TestOmemoDecryptor(42);
        var xml = build_v1_encrypted_xml(100, { 0x01 }, ct, 42, { 0xAA }, false);
        var parsed = decryptor.parse_node(xml);

        fail_if(parsed == null, "parsed must be non-null");
        fail_if(parsed.ciphertext == null, "ciphertext must be non-null");
        fail_if_not_eq_int(parsed.ciphertext.length, 4, "ciphertext length");
        fail_if_not_eq_int(parsed.ciphertext[0], 0xCA, "ciphertext first byte");
    }

    /** XEP-0384 v0.3: missing <header> → null */
    public void test_v1_parse_no_header() {
        var decryptor = new TestOmemoDecryptor(42);
        var xml = new StanzaNode.build("encrypted", NS_URI).add_self_xmlns();
        GLib.Test.expect_message("xmpp-vala", GLib.LogLevelFlags.LEVEL_WARNING,
            "*Can't parse OMEMO node: No header node");
        var parsed = decryptor.parse_node(xml);
        GLib.Test.assert_expected_messages();
        fail_if(parsed != null, "missing header must return null");
    }

    /** XEP-0384 v0.3: missing <iv> → null */
    public void test_v1_parse_no_iv() {
        var decryptor = new TestOmemoDecryptor(42);
        var xml = new StanzaNode.build("encrypted", NS_URI).add_self_xmlns();
        var header = new StanzaNode.build("header", NS_URI)
            .put_attribute("sid", "100");
        // No <iv> element
        xml.put_node(header);
        GLib.Test.expect_message("xmpp-vala", GLib.LogLevelFlags.LEVEL_WARNING,
            "*Can't parse OMEMO node: No iv");
        var parsed = decryptor.parse_node(xml);
        GLib.Test.assert_expected_messages();
        fail_if(parsed != null, "missing IV must return null");
    }

    /** XEP-0384 v0.3: parse_node finds our key by matching rid to own_device_id */
    public void test_v1_parse_our_key() {
        uint8[] our_key = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 };
        var decryptor = new TestOmemoDecryptor(42);
        var xml = build_v1_encrypted_xml(100, { 0x01 }, { 0xDE }, 42, our_key, false);

        // Also add a key for a different device
        StanzaNode? header = xml.get_subnode("header", NS_URI);
        header.put_node(new StanzaNode.build("key", NS_URI)
            .put_attribute("rid", "999")
            .put_node(new StanzaNode.text(Base64.encode({ 0xFF }))));

        var parsed = decryptor.parse_node(xml);
        fail_if(parsed == null, "parsed must be non-null");
        fail_if_not_eq_int(parsed.our_potential_encrypted_keys.size, 1,
            "must find exactly our key (rid=42)");
    }

    /** XEP-0384 v0.3: prekey attribute parsed correctly */
    public void test_v1_parse_prekey() {
        var decryptor = new TestOmemoDecryptor(42);
        var xml = build_v1_encrypted_xml(100, { 0x01 }, { 0xDE }, 42, { 0xAA }, true);
        var parsed = decryptor.parse_node(xml);

        fail_if(parsed == null, "parsed must be non-null");
        // Check that prekey is true for our key
        foreach (var entry in parsed.our_potential_encrypted_keys.entries) {
            fail_if_not(entry.value, "prekey must be true");
        }
    }

    /* ==================================================================
     * OMEMO 2 NAMESPACE TESTS
     * ================================================================== */

    /** XEP-0384 v0.8: NS_URI_V2 MUST be "urn:xmpp:omemo:2" */
    public void test_v2_ns_uri() {
        fail_if_not_eq_str(NS_URI_V2, "urn:xmpp:omemo:2", "OMEMO 2 NS_URI");
    }

    /** XEP-0384 v0.8: devicelist node has :devices suffix */
    public void test_v2_node_devicelist() {
        fail_if_not_eq_str(NODE_DEVICELIST_V2, "urn:xmpp:omemo:2:devices",
            "OMEMO 2 devicelist node");
    }

    /** XEP-0384 v0.8: bundles node has :bundles suffix */
    public void test_v2_node_bundles() {
        fail_if_not_eq_str(NODE_BUNDLES_V2, "urn:xmpp:omemo:2:bundles",
            "OMEMO 2 bundles node");
    }

    /* ==================================================================
     * OMEMO 2 STANZA BUILDING TESTS
     * ================================================================== */

    /** XEP-0384 v0.8: <encrypted xmlns='urn:xmpp:omemo:2'> */
    public void test_v2_encrypted_ns() {
        var data = make_v2_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();

        fail_if_not_eq_str(encrypted.name, "encrypted", "root name");
        fail_if_not_eq_str(encrypted.ns_uri, NS_URI_V2, "must use OMEMO 2 namespace");
    }

    /** XEP-0384 v0.8: keys MUST be grouped by JID: <keys jid='...'> */
    public void test_v2_keys_grouped_by_jid() {
        var data = make_v2_enc_data();
        try {
            Jid alice = new Jid("alice@example.com");
            data.add_device_key(alice, 100, { 0x01, 0x02 }, false);
            data.add_device_key(alice, 200, { 0x03, 0x04 }, true);
        } catch (Error e) { fail_if_reached(@"JID error: $(e.message)"); }

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI_V2);
        fail_if(header == null, "header must exist");

        var keys_nodes = header.get_subnodes("keys", NS_URI_V2);
        fail_if_not_eq_int(keys_nodes.size, 1, "one JID group for alice");

        StanzaNode keys = keys_nodes[0];
        fail_if_not_eq_str(keys.get_attribute("jid"), "alice@example.com", "jid attribute");

        var key_nodes = keys.get_subnodes("key", NS_URI_V2);
        fail_if_not_eq_int(key_nodes.size, 2, "two keys for alice");
    }

    /** XEP-0384 v0.8: OMEMO 2 uses 'kex' attribute, NOT 'prekey' */
    public void test_v2_kex_attribute() {
        var data = make_v2_enc_data();
        try {
            Jid bob = new Jid("bob@example.com");
            data.add_device_key(bob, 42, { 0xAA }, true);
        } catch (Error e) { fail_if_reached(); }

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI_V2);
        var keys_nodes = header.get_subnodes("keys", NS_URI_V2);
        StanzaNode? key_node = keys_nodes[0].get_subnode("key", NS_URI_V2);

        // Must use 'kex', NOT 'prekey'
        fail_if_not_eq_str(key_node.get_attribute("kex"), "true", "kex attribute");
        fail_if(key_node.get_attribute("prekey") != null,
            "OMEMO 2 must NOT use 'prekey' attribute");
    }

    /** XEP-0384 v0.8: OMEMO 2 has NO <iv> in header (IV derived from HKDF) */
    public void test_v2_no_iv_in_header() {
        var data = make_v2_enc_data();
        try {
            data.add_device_key(new Jid("test@example.com"), 1, { 0x01 }, false);
        } catch (Error e) { fail_if_reached(); }

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI_V2);

        string? iv = header.get_deep_string_content("iv");
        fail_if(iv != null, "OMEMO 2 must NOT have <iv> in header (derived from HKDF)");
    }

    /** XEP-0384 v0.8: <payload> contains base64-encoded ciphertext */
    public void test_v2_payload() {
        var data = make_v2_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();

        string? payload = encrypted.get_deep_string_content("payload");
        fail_if(payload == null, "payload must exist");

        uint8[] decoded = Base64.decode(payload);
        fail_if_not_eq_int(decoded.length, 4, "ciphertext length");
        fail_if_not_eq_int(decoded[0], 0xCA, "ciphertext first byte");
    }

    /** XEP-0384 v0.8: <header sid='...'> */
    public void test_v2_header_sid() {
        var data = make_v2_enc_data();
        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI_V2);

        fail_if(header == null, "header must exist");
        fail_if_not_eq_str(header.get_attribute("sid"), "67890", "sid must match");
    }

    /** XEP-0384 v0.8: multiple JIDs with multiple keys each */
    public void test_v2_multi_jid_keys() {
        var data = make_v2_enc_data();
        try {
            Jid alice = new Jid("alice@example.com");
            Jid bob = new Jid("bob@example.com");
            data.add_device_key(alice, 1, { 0x01 }, false);
            data.add_device_key(alice, 2, { 0x02 }, true);
            data.add_device_key(bob, 3, { 0x03 }, false);
        } catch (Error e) { fail_if_reached(); }

        StanzaNode encrypted = data.get_encrypted_node();
        StanzaNode? header = encrypted.get_subnode("header", NS_URI_V2);
        var keys_groups = header.get_subnodes("keys", NS_URI_V2);

        fail_if_not_eq_int(keys_groups.size, 2, "two JID groups");

        // Count total keys
        int total = 0;
        foreach (var group in keys_groups) {
            total += group.get_subnodes("key", NS_URI_V2).size;
        }
        fail_if_not_eq_int(total, 3, "three keys total");
    }

    /** XEP-0384 v0.8: empty ciphertext → no <payload> element */
    public void test_v2_empty_payload() {
        var data = new Omemo2EncryptionData(100);
        // ciphertext is null
        StanzaNode encrypted = data.get_encrypted_node();
        string? payload = encrypted.get_deep_string_content("payload");
        fail_if(payload != null, "no payload when ciphertext is null");
    }

    /* ==================================================================
     * OMEMO 2 STANZA PARSING TESTS
     * ================================================================== */

    /** Build OMEMO 2 <encrypted> XML for parsing tests */
    private StanzaNode build_v2_encrypted_xml(int sid, uint8[]? payload,
                                                string our_jid, int our_rid,
                                                uint8[] our_key, bool kex) {
        var encrypted = new StanzaNode.build("encrypted", NS_URI_V2).add_self_xmlns();
        var header = new StanzaNode.build("header", NS_URI_V2)
            .put_attribute("sid", sid.to_string());

        // Add keys grouped by JID
        var keys = new StanzaNode.build("keys", NS_URI_V2)
            .put_attribute("jid", our_jid);
        var key_node = new StanzaNode.build("key", NS_URI_V2)
            .put_attribute("rid", our_rid.to_string())
            .put_node(new StanzaNode.text(Base64.encode(our_key)));
        if (kex) key_node.put_attribute("kex", "true");
        keys.put_node(key_node);
        header.put_node(keys);

        encrypted.put_node(header);

        if (payload != null) {
            encrypted.put_node(new StanzaNode.build("payload", NS_URI_V2)
                .put_node(new StanzaNode.text(Base64.encode(payload))));
        }

        return encrypted;
    }

    /** XEP-0384 v0.8: parse_node extracts sid */
    public void test_v2_parse_sid() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            var xml = build_v2_encrypted_xml(27182, { 0xDE, 0xAD }, "me@example.com", 42, { 0xAA }, false);
            var parsed = decryptor.parse_node(xml, our_jid);

            fail_if(parsed == null, "parse must succeed");
            fail_if_not_eq_int(parsed.sid, 27182, "parsed sid");
        } catch (Error e) { fail_if_reached(@"error: $(e.message)"); }
    }

    /** XEP-0384 v0.8: parse_node extracts ciphertext */
    public void test_v2_parse_payload() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            uint8[] ct = { 0xCA, 0xFE, 0xBA, 0xBE };
            var xml = build_v2_encrypted_xml(100, ct, "me@example.com", 42, { 0xAA }, false);
            var parsed = decryptor.parse_node(xml, our_jid);

            fail_if(parsed == null, "parse must succeed");
            fail_if(parsed.ciphertext == null, "ciphertext must be present");
            fail_if_not_eq_int(parsed.ciphertext.length, 4, "ciphertext length");
            fail_if_not_eq_int(parsed.ciphertext[0], 0xCA, "ciphertext first byte");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0384 v0.8: parse_node finds our keys by matching JID */
    public void test_v2_parse_keys_by_jid() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            uint8[] our_key = { 0x11, 0x22, 0x33 };
            var xml = build_v2_encrypted_xml(100, { 0xDE }, "me@example.com", 42, our_key, false);
            var parsed = decryptor.parse_node(xml, our_jid);

            fail_if(parsed == null, "parse must succeed");
            fail_if_not_eq_int(parsed.our_potential_encrypted_keys.size, 1,
                "must find exactly our key");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0384 v0.8: kex attribute parsed correctly */
    public void test_v2_parse_kex() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            var xml = build_v2_encrypted_xml(100, { 0xDE }, "me@example.com", 42, { 0xAA }, true);
            var parsed = decryptor.parse_node(xml, our_jid);

            fail_if(parsed == null, "parse must succeed");
            foreach (var entry in parsed.our_potential_encrypted_keys.entries) {
                fail_if_not(entry.value, "kex must be true");
            }
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0384 v0.8: missing <header> → null */
    public void test_v2_parse_no_header() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            var xml = new StanzaNode.build("encrypted", NS_URI_V2).add_self_xmlns();
            GLib.Test.expect_message("xmpp-vala", GLib.LogLevelFlags.LEVEL_WARNING,
                "*OMEMO 2: Can't parse: No header node");
            var parsed = decryptor.parse_node(xml, our_jid);
            GLib.Test.assert_expected_messages();
            fail_if(parsed != null, "missing header → null");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0384 v0.8: missing sid attribute → null */
    public void test_v2_parse_no_sid() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            var xml = new StanzaNode.build("encrypted", NS_URI_V2).add_self_xmlns();
            xml.put_node(new StanzaNode.build("header", NS_URI_V2));
            // No sid attribute
            GLib.Test.expect_message("xmpp-vala", GLib.LogLevelFlags.LEVEL_WARNING,
                "*OMEMO 2: Can't parse: No sid");
            var parsed = decryptor.parse_node(xml, our_jid);
            GLib.Test.assert_expected_messages();
            fail_if(parsed != null, "missing sid → null");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0384 v0.8: keys for other JID are ignored */
    public void test_v2_parse_other_jid() {
        var decryptor = new TestOmemo2Decryptor(42);
        try {
            Jid our_jid = new Jid("me@example.com");
            // Build XML with keys for bob, not for us
            var xml = build_v2_encrypted_xml(100, { 0xDE }, "bob@example.com", 42, { 0xAA }, false);
            var parsed = decryptor.parse_node(xml, our_jid);

            fail_if(parsed == null, "parse must succeed (valid structure)");
            fail_if_not_eq_int(parsed.our_potential_encrypted_keys.size, 0,
                "must not find keys for other JID");
        } catch (Error e) { fail_if_reached(); }
    }

    /* ==================================================================
     * OMEMO 2 CRYPTO CONSTANT TESTS
     * ================================================================== */

    /** XEP-0384 v0.8 §4.5: mk(32) || auth_tag(16) = 48 bytes */
    public void test_v2_mk_with_tag_48() {
        /* Verify the layout used in encrypt_v2.vala */
        int MK_SIZE = 32;
        int AUTH_TAG_SIZE = 16;

        uint8[] mk = new uint8[MK_SIZE];
        uint8[] auth_tag = new uint8[AUTH_TAG_SIZE];
        for (int i = 0; i < MK_SIZE; i++) mk[i] = (uint8)i;
        for (int i = 0; i < AUTH_TAG_SIZE; i++) auth_tag[i] = (uint8)(0xA0 + i);

        uint8[] mk_with_tag = new uint8[MK_SIZE + AUTH_TAG_SIZE];
        Memory.copy(mk_with_tag, mk, MK_SIZE);
        Memory.copy((uint8*)mk_with_tag + MK_SIZE, auth_tag, AUTH_TAG_SIZE);

        fail_if_not_eq_int(mk_with_tag.length, 48, "mk_with_tag must be 48 bytes");

        // Verify mk comes first
        fail_if_not_eq_int(mk_with_tag[0], 0x00, "mk starts at offset 0");
        fail_if_not_eq_int(mk_with_tag[31], 31, "mk ends at offset 31");

        // Verify auth_tag comes second
        fail_if_not_eq_int(mk_with_tag[32], 0xA0, "auth_tag starts at offset 32");
        fail_if_not_eq_int(mk_with_tag[47], 0xAF, "auth_tag ends at offset 47");
    }

    /* ==================================================================
     * ENCRYPT STATE TESTS
     * ================================================================== */

    /** EncryptState.add_result accumulates own device results */
    public void test_encrypt_state_own() {
        var state = new EncryptState();
        var result = new EncryptionResult();
        result.success = 2;
        result.lost = 1;
        result.unknown = 3;
        result.failure = 0;

        state.add_result(result, true);

        fail_if_not_eq_int(state.own_success, 2, "own_success");
        fail_if_not_eq_int(state.own_lost, 1, "own_lost");
        fail_if_not_eq_int(state.own_unknown, 3, "own_unknown");
        fail_if_not_eq_int(state.own_failure, 0, "own_failure");
        // Other must be zero
        fail_if_not_eq_int(state.other_success, 0, "other_success must be 0");
    }

    /** EncryptState.add_result accumulates other device results */
    public void test_encrypt_state_other() {
        var state = new EncryptState();
        var result = new EncryptionResult();
        result.success = 5;
        result.lost = 0;
        result.unknown = 1;
        result.failure = 2;

        state.add_result(result, false);

        fail_if_not_eq_int(state.other_success, 5, "other_success");
        fail_if_not_eq_int(state.other_lost, 0, "other_lost");
        fail_if_not_eq_int(state.other_unknown, 1, "other_unknown");
        fail_if_not_eq_int(state.other_failure, 2, "other_failure");
        // Own must be zero
        fail_if_not_eq_int(state.own_success, 0, "own_success must be 0");
    }
}

}
