/**
 * Security audit tests for OMEMO Bundle XML parsers.
 *
 * Tests Bundle (v1, XEP-0384 v0.3) and Bundle2 (v2, XEP-0384 v0.8)
 * XML parsing against untrusted input: null nodes, missing elements,
 * non-numeric IDs, malformed base64.
 *
 * The Bundle/Bundle2 classes are public, so no visibility change needed.
 * They do call Plugin.ensure_context() in their constructors.
 */

using Dino.Plugins.Omemo;
using Xmpp;

namespace Omemo.Test {

class BundleParserTest : Gee.TestCase {

    private const string NS_V1 = "eu.siacs.conversations.axolotl";
    private const string NS_V2 = "urn:xmpp:omemo:2";

    public BundleParserTest() {
        base("BundleParser");

        /* Bundle v1 */
        add_test("XEP0384v03_bundle_null_node_spk_id_minus1", test_v1_null_node);
        add_test("XEP0384v03_bundle_missing_spk_node", test_v1_missing_spk);
        add_test("XEP0384v03_bundle_valid_spk_id", test_v1_valid_spk_id);
        add_test("XEP0384v03_bundle_non_numeric_spk_id", test_v1_non_numeric_spk_id);
        add_test("XEP0384v03_bundle_empty_prekeys", test_v1_empty_prekeys);
        add_test("XEP0384v03_bundle_prekey_id_parsed", test_v1_prekey_id);
        add_test("XEP0384v03_bundle_prekey_missing_id_skipped", test_v1_prekey_missing_id);

        /* Bundle v2 */
        add_test("XEP0384v08_bundle_null_node_spk_id_minus1", test_v2_null_node);
        add_test("XEP0384v08_bundle_missing_spk_node", test_v2_missing_spk);
        add_test("XEP0384v08_bundle_valid_spk_id", test_v2_valid_spk_id);
        add_test("XEP0384v08_bundle_non_numeric_spk_id", test_v2_non_numeric_spk_id);
        add_test("XEP0384v08_bundle_empty_prekeys", test_v2_empty_prekeys);
        add_test("XEP0384v08_bundle_prekey_id_parsed", test_v2_prekey_id);
        add_test("XEP0384v08_bundle_prekey_no_id_skipped", test_v2_prekey_no_id);
        add_test("XEP0384v08_bundle_missing_sig_null", test_v2_missing_sig);
        add_test("XEP0384v08_bundle_missing_ik_null", test_v2_missing_ik);
    }

    /* ===== Bundle v1 tests ===== */

    /**
     * XEP-0384 v0.3: Null node → signed_pre_key_id returns -1.
     */
    private void test_v1_null_node() {
        var bundle = new Bundle(null);
        fail_if_not_eq_int(bundle.signed_pre_key_id, -1,
            "XEP-0384 v0.3: null node must return spk_id -1");
    }

    /**
     * XEP-0384 v0.3: Missing signedPreKeyPublic node → -1.
     */
    private void test_v1_missing_spk() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns();
        var bundle = new Bundle(node);
        fail_if_not_eq_int(bundle.signed_pre_key_id, -1,
            "XEP-0384 v0.3: missing signedPreKeyPublic must return -1");
    }

    /**
     * XEP-0384 v0.3: Valid signedPreKeyId attribute.
     */
    private void test_v1_valid_spk_id() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns()
            .put_node(new StanzaNode.build("signedPreKeyPublic", NS_V1)
                .put_attribute("signedPreKeyId", "42")
                .put_node(new StanzaNode.text("AAAA")));
        var bundle = new Bundle(node);
        fail_if_not_eq_int(bundle.signed_pre_key_id, 42,
            "XEP-0384 v0.3: signedPreKeyId=42 must parse correctly");
    }

    /**
     * XEP-0384 v0.3: Non-numeric signedPreKeyId → int.parse returns 0.
     *
     * FINDING: int.parse("garbage") returns 0, which is indistinguishable
     * from a legitimate key ID of 0. This could cause key confusion.
     */
    private void test_v1_non_numeric_spk_id() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns()
            .put_node(new StanzaNode.build("signedPreKeyPublic", NS_V1)
                .put_attribute("signedPreKeyId", "garbage")
                .put_node(new StanzaNode.text("AAAA")));
        var bundle = new Bundle(node);
        // int.parse("garbage") = 0 in GLib (strtol behavior)
        // This is NOT -1, so it looks like a valid key ID!
        int parsed_id = bundle.signed_pre_key_id;
        // Document the behavior: non-numeric → 0 (not -1)
        fail_if_not_eq_int(parsed_id, 0,
            "int.parse on non-numeric returns 0 (FINDING: ambiguous with valid id=0)");
    }

    /**
     * XEP-0384 v0.3: Missing prekeys node → empty list.
     */
    private void test_v1_empty_prekeys() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns();
        var bundle = new Bundle(node);
        fail_if_not_eq_int(bundle.pre_keys.size, 0,
            "XEP-0384 v0.3: missing prekeys must return empty list");
    }

    /**
     * XEP-0384 v0.3: PreKey with valid ID.
     */
    private void test_v1_prekey_id() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns()
            .put_node(new StanzaNode.build("prekeys", NS_V1)
                .put_node(new StanzaNode.build("preKeyPublic", NS_V1)
                    .put_attribute("preKeyId", "7")
                    .put_node(new StanzaNode.text("AAAA"))));
        var bundle = new Bundle(node);
        fail_if_not_eq_int(bundle.pre_keys.size, 1,
            "XEP-0384 v0.3: one prekey must be parsed");
        fail_if_not_eq_int(bundle.pre_keys[0].key_id, 7,
            "XEP-0384 v0.3: prekey id must be 7");
    }

    /**
     * XEP-0384 v0.3: PreKey without preKeyId attribute → skipped by filter.
     */
    private void test_v1_prekey_missing_id() {
        var node = new StanzaNode.build("bundle", NS_V1).add_self_xmlns()
            .put_node(new StanzaNode.build("prekeys", NS_V1)
                .put_node(new StanzaNode.build("preKeyPublic", NS_V1)
                    .put_node(new StanzaNode.text("AAAA"))));
        var bundle = new Bundle(node);
        // The filter checks get_attribute("preKeyId") != null
        fail_if_not_eq_int(bundle.pre_keys.size, 0,
            "XEP-0384 v0.3: prekey without preKeyId must be filtered out");
    }

    /* ===== Bundle v2 tests ===== */

    /**
     * XEP-0384 v0.8: Null node → signed_pre_key_id returns -1.
     */
    private void test_v2_null_node() {
        var bundle = new Bundle2(null);
        fail_if_not_eq_int(bundle.signed_pre_key_id, -1,
            "XEP-0384 v0.8: null node must return spk_id -1");
    }

    /**
     * XEP-0384 v0.8: Missing spk node → -1.
     */
    private void test_v2_missing_spk() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns();
        var bundle = new Bundle2(node);
        fail_if_not_eq_int(bundle.signed_pre_key_id, -1,
            "XEP-0384 v0.8: missing spk node must return -1");
    }

    /**
     * XEP-0384 v0.8: Valid spk id attribute.
     */
    private void test_v2_valid_spk_id() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns()
            .put_node(new StanzaNode.build("spk", NS_V2)
                .put_attribute("id", "99")
                .put_node(new StanzaNode.text("AAAA")));
        var bundle = new Bundle2(node);
        fail_if_not_eq_int(bundle.signed_pre_key_id, 99,
            "XEP-0384 v0.8: spk id=99 must parse correctly");
    }

    /**
     * XEP-0384 v0.8: Non-numeric spk id → int.parse returns 0.
     */
    private void test_v2_non_numeric_spk_id() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns()
            .put_node(new StanzaNode.build("spk", NS_V2)
                .put_attribute("id", "not-a-number")
                .put_node(new StanzaNode.text("AAAA")));
        var bundle = new Bundle2(node);
        int parsed_id = bundle.signed_pre_key_id;
        fail_if_not_eq_int(parsed_id, 0,
            "int.parse on non-numeric returns 0 (FINDING: same as v1)");
    }

    /**
     * XEP-0384 v0.8: Missing prekeys → empty list.
     */
    private void test_v2_empty_prekeys() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns();
        var bundle = new Bundle2(node);
        fail_if_not_eq_int(bundle.pre_keys.size, 0,
            "XEP-0384 v0.8: missing prekeys must return empty list");
    }

    /**
     * XEP-0384 v0.8: PreKey with valid ID.
     */
    private void test_v2_prekey_id() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns()
            .put_node(new StanzaNode.build("prekeys", NS_V2)
                .put_node(new StanzaNode.build("pk", NS_V2)
                    .put_attribute("id", "5")
                    .put_node(new StanzaNode.text("AAAA"))));
        var bundle = new Bundle2(node);
        fail_if_not_eq_int(bundle.pre_keys.size, 1,
            "XEP-0384 v0.8: one prekey must be parsed");
        fail_if_not_eq_int(bundle.pre_keys[0].key_id, 5,
            "XEP-0384 v0.8: prekey id must be 5");
    }

    /**
     * XEP-0384 v0.8: PreKey without id attribute → skipped.
     */
    private void test_v2_prekey_no_id() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns()
            .put_node(new StanzaNode.build("prekeys", NS_V2)
                .put_node(new StanzaNode.build("pk", NS_V2)
                    .put_node(new StanzaNode.text("AAAA"))));
        var bundle = new Bundle2(node);
        fail_if_not_eq_int(bundle.pre_keys.size, 0,
            "XEP-0384 v0.8: pk without id must be filtered out");
    }

    /**
     * XEP-0384 v0.8: Missing spks (signature) node → null.
     */
    private void test_v2_missing_sig() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns();
        var bundle = new Bundle2(node);
        fail_if(bundle.signed_pre_key_signature != null,
            "XEP-0384 v0.8: missing spks must return null signature");
    }

    /**
     * XEP-0384 v0.8: Missing ik (identity key) node → null.
     */
    private void test_v2_missing_ik() {
        var node = new StanzaNode.build("bundle", NS_V2).add_self_xmlns();
        var bundle = new Bundle2(node);
        fail_if(bundle.identity_key != null,
            "XEP-0384 v0.8: missing ik must return null identity key");
    }
}

}
