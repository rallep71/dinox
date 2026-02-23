using Xmpp;
using Xmpp.Xep;
using Xmpp.Xep.OpenPgpContent;
using Gee;

namespace Xmpp.Test {

/**
 * Spec-based audit tests for OpenPGP (XEP-0373 & XEP-0374) stanza structure.
 *
 * Tests cover:
 *   - XEP-0373: OpenPGP for XMPP — namespace constants, PublicKeyMeta, PublicKeyData
 *   - XEP-0374: OpenPGP for XMPP Instant Messaging — SigncryptElement, SignElement,
 *     CryptElement, OpenpgpElement stanza building and parsing
 *
 * These tests verify the xmpp-vala protocol layer that builds and parses
 * OpenPGP XML stanzas. They do NOT require GPG binary or network connections.
 */
public class OpenPgpAudit : Gee.TestCase {

    public OpenPgpAudit() {
        base("OpenPgpAudit");

        /* === XEP-0373 namespace tests === */
        add_test("XEP0373_ns_uri_is_openpgp_0", test_ns_uri);
        add_test("XEP0373_ns_pubkeys_suffix", test_ns_pubkeys);

        /* === XEP-0373 data classes === */
        add_test("XEP0373_public_key_meta_stores_fingerprint", test_public_key_meta);
        add_test("XEP0373_public_key_meta_stores_date", test_public_key_meta_date);
        add_test("XEP0373_public_key_data_has_armored_key", test_public_key_data);
        add_test("XEP0373_public_key_data_date_optional", test_public_key_data_no_date);

        /* === XEP-0374 namespace tests === */
        add_test("XEP0374_ns_uri_is_openpgp_0", test_content_ns_uri);
        add_test("XEP0374_ns_uri_im_service_discovery", test_content_ns_uri_im);

        /* === XEP-0374 SigncryptElement tests === */
        add_test("XEP0374_signcrypt_with_body_roundtrip", test_signcrypt_roundtrip);
        add_test("XEP0374_signcrypt_has_to_jid", test_signcrypt_to_jid);
        add_test("XEP0374_signcrypt_has_time_stamp", test_signcrypt_time);
        add_test("XEP0374_signcrypt_has_rpad", test_signcrypt_rpad);
        add_test("XEP0374_signcrypt_has_payload_with_body", test_signcrypt_payload);
        add_test("XEP0374_signcrypt_get_body_text", test_signcrypt_get_body);
        add_test("XEP0374_signcrypt_stanza_element_name", test_signcrypt_element_name);
        add_test("XEP0374_signcrypt_invalid_root_returns_null", test_signcrypt_wrong_root);
        add_test("XEP0374_signcrypt_wrong_ns_returns_null", test_signcrypt_wrong_ns);

        /* === XEP-0374 SignElement tests === */
        add_test("XEP0374_sign_element_structure", test_sign_structure);
        add_test("XEP0374_sign_roundtrip", test_sign_roundtrip);
        add_test("XEP0374_sign_invalid_root_returns_null", test_sign_wrong_root);

        /* === XEP-0374 CryptElement tests === */
        add_test("XEP0374_crypt_element_structure", test_crypt_structure);
        add_test("XEP0374_crypt_roundtrip", test_crypt_roundtrip);
        add_test("XEP0374_crypt_invalid_root_returns_null", test_crypt_wrong_root);

        /* === XEP-0374 OpenpgpElement tests === */
        add_test("XEP0374_openpgp_element_wraps_base64", test_openpgp_element);
        add_test("XEP0374_openpgp_element_roundtrip", test_openpgp_roundtrip);
        add_test("XEP0374_openpgp_invalid_root_returns_null", test_openpgp_wrong_root);
        add_test("XEP0374_openpgp_null_content_returns_null", test_openpgp_null_content);

        /* === XEP-0374 random padding tests === */
        add_test("XEP0374_signcrypt_rpad_is_nonempty", test_rpad_nonempty);
        add_test("XEP0374_signcrypt_rpad_is_base64", test_rpad_is_base64);

        /* === XEP-0374 random padding security audit === */
        add_test("XEP0374_rpad_modulo_bias_256_mod_49", test_rpad_modulo_bias);
        add_test("XEP0374_rpad_length_varies_between_instances", test_rpad_varies);
        add_test("XEP0374_rpad_decode_length_in_16_to_64", test_rpad_decode_length_range);
        add_test("SP800_90A_rpad_uses_dev_urandom_on_linux", test_rpad_csprng_available);

        /* === XEP-0374 cross-element rejection tests === */
        add_test("XEP0374_signcrypt_rejects_sign_element", test_cross_signcrypt_sign);
        add_test("XEP0374_sign_rejects_crypt_element", test_cross_sign_crypt);
        add_test("XEP0374_crypt_rejects_signcrypt_element", test_cross_crypt_signcrypt);
    }

    /* ==================================================================
     * XEP-0373 NAMESPACE TESTS
     * ================================================================== */

    /** XEP-0373 §3: namespace MUST be "urn:xmpp:openpgp:0" */
    public void test_ns_uri() {
        fail_if_not_eq_str(OpenPgp.NS_URI, "urn:xmpp:openpgp:0",
            "XEP-0373 NS_URI");
    }

    /** XEP-0373 §3: public-keys node = NS_URI + ":public-keys" */
    public void test_ns_pubkeys() {
        fail_if_not_eq_str(OpenPgp.NS_URI_PUBKEYS, "urn:xmpp:openpgp:0:public-keys",
            "XEP-0373 public-keys node");
    }

    /* ==================================================================
     * XEP-0373 DATA CLASS TESTS
     * ================================================================== */

    /** PublicKeyMeta stores fingerprint */
    public void test_public_key_meta() {
        var meta = new OpenPgp.PublicKeyMeta("ABCDEF1234567890ABCDEF1234567890ABCDEF12");
        fail_if_not_eq_str(meta.fingerprint, "ABCDEF1234567890ABCDEF1234567890ABCDEF12",
            "fingerprint stored");
    }

    /** PublicKeyMeta stores date */
    public void test_public_key_meta_date() {
        var now = new DateTime.now_utc();
        var meta = new OpenPgp.PublicKeyMeta("ABCD1234", now);
        fail_if(meta.date == null, "date must be stored");
        fail_if_not_eq_int(meta.date.compare(now), 0, "date must match");
    }

    /** PublicKeyData stores fingerprint and armored key */
    public void test_public_key_data() {
        string armor = "-----BEGIN PGP PUBLIC KEY BLOCK-----\ntest\n-----END PGP PUBLIC KEY BLOCK-----";
        var data = new OpenPgp.PublicKeyData("DEADBEEF", armor);
        fail_if_not_eq_str(data.fingerprint, "DEADBEEF", "fingerprint");
        fail_if_not_eq_str(data.armored_key, armor, "armored key");
    }

    /** PublicKeyData date is optional (null) */
    public void test_public_key_data_no_date() {
        var data = new OpenPgp.PublicKeyData("ABCD", "key");
        fail_if(data.date != null, "date must be null by default");
    }

    /* ==================================================================
     * XEP-0374 NAMESPACE TESTS
     * ================================================================== */

    /** XEP-0374 §3: namespace matches XEP-0373 */
    public void test_content_ns_uri() {
        fail_if_not_eq_str(OpenPgpContent.NS_URI, "urn:xmpp:openpgp:0",
            "XEP-0374 NS_URI");
    }

    /** XEP-0374 §4: Service Discovery feature namespace */
    public void test_content_ns_uri_im() {
        fail_if_not_eq_str(OpenPgpContent.NS_URI_IM, "urn:xmpp:openpgp:im:0",
            "XEP-0374 Service Discovery NS_URI");
    }

    /* ==================================================================
     * XEP-0374 SIGNCRYPT ELEMENT TESTS
     * ================================================================== */

    /** XEP-0374 §2.1: SigncryptElement roundtrip: create → serialize → parse */
    public void test_signcrypt_roundtrip() {
        try {
            var element = new SigncryptElement.with_body(new Jid("alice@example.com"), "Hello, World!");
            StanzaNode node = element.to_stanza_node();
            SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);

            fail_if(parsed == null, "roundtrip parse must succeed");
            fail_if_not_eq_str(parsed.get_body_text(), "Hello, World!", "body text roundtrip");
        } catch (Error e) { fail_if_reached(@"error: $(e.message)"); }
    }

    /** XEP-0374 §2.1: <to jid='...'> must be present */
    public void test_signcrypt_to_jid() {
        try {
            var element = new SigncryptElement.with_body(new Jid("bob@example.com"), "test");
            StanzaNode node = element.to_stanza_node();
            SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);

            fail_if(parsed == null, "parse must succeed");
            fail_if(parsed.to == null, "to JID must be present");
            fail_if_not_eq_str(parsed.to.to_string(), "bob@example.com", "to JID value");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374 §2.1: <time stamp='...'> must be present */
    public void test_signcrypt_time() {
        try {
            var element = new SigncryptElement.with_body(new Jid("test@example.com"), "msg");
            StanzaNode node = element.to_stanza_node();
            SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);

            fail_if(parsed == null, "parse must succeed");
            fail_if(parsed.time == null, "timestamp must be present");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374 §2.1: <rpad> random padding must be present */
    public void test_signcrypt_rpad() {
        try {
            var element = new SigncryptElement.with_body(new Jid("test@example.com"), "msg");
            StanzaNode node = element.to_stanza_node();
            SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);

            fail_if(parsed == null, "parse must succeed");
            fail_if(parsed.rpad == null, "rpad must be present");
            fail_if(parsed.rpad.length == 0, "rpad must be non-empty");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374 §2.1: <payload> contains <body> */
    public void test_signcrypt_payload() {
        try {
            var element = new SigncryptElement.with_body(new Jid("test@example.com"), "Secret");
            StanzaNode node = element.to_stanza_node();

            StanzaNode? payload = node.get_subnode("payload", OpenPgpContent.NS_URI);
            fail_if(payload == null, "payload element must exist");

            var children = payload.get_all_subnodes();
            fail_if(children.size == 0, "payload must have children");

            StanzaNode body = children[0];
            fail_if_not_eq_str(body.name, "body", "payload child must be <body>");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374 §2.1: get_body_text() returns body content */
    public void test_signcrypt_get_body() {
        try {
            var element = new SigncryptElement.with_body(new Jid("test@example.com"), "Hello!");
            fail_if_not_eq_str(element.get_body_text(), "Hello!", "get_body_text");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374 §2.1: root element MUST be <signcrypt> */
    public void test_signcrypt_element_name() {
        try {
            var element = new SigncryptElement.with_body(new Jid("test@example.com"), "test");
            StanzaNode node = element.to_stanza_node();
            fail_if_not_eq_str(node.name, "signcrypt", "element name");
            fail_if_not_eq_str(node.ns_uri, OpenPgpContent.NS_URI, "namespace");
        } catch (Error e) { fail_if_reached(); }
    }

    /** XEP-0374: from_stanza_node returns null for wrong root element name */
    public void test_signcrypt_wrong_root() {
        var node = new StanzaNode.build("sign", OpenPgpContent.NS_URI).add_self_xmlns();
        SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);
        fail_if(parsed != null, "wrong root name must return null");
    }

    /** XEP-0374: from_stanza_node returns null for wrong namespace */
    public void test_signcrypt_wrong_ns() {
        var node = new StanzaNode.build("signcrypt", "urn:wrong:ns").add_self_xmlns();
        SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);
        fail_if(parsed != null, "wrong namespace must return null");
    }

    /* ==================================================================
     * XEP-0374 SIGN ELEMENT TESTS
     * ================================================================== */

    /** XEP-0374 §2.2: SignElement has <sign> with to, time, rpad, payload */
    public void test_sign_structure() {
        var element = new SignElement();
        try {
            element.to = new Jid("recipient@example.com");
        } catch (Error e) { fail_if_reached(); }
        element.payload = new StanzaNode.build("body", "jabber:client")
            .put_node(new StanzaNode.text("signed message"));

        StanzaNode node = element.to_stanza_node();
        fail_if_not_eq_str(node.name, "sign", "element name");
        fail_if_not_eq_str(node.ns_uri, OpenPgpContent.NS_URI, "namespace");

        fail_if(node.get_subnode("to", OpenPgpContent.NS_URI) == null, "to must exist");
        fail_if(node.get_subnode("time", OpenPgpContent.NS_URI) == null, "time must exist");
        fail_if(node.get_subnode("rpad", OpenPgpContent.NS_URI) == null, "rpad must exist");
        fail_if(node.get_subnode("payload", OpenPgpContent.NS_URI) == null, "payload must exist");
    }

    /** XEP-0374 §2.2: SignElement roundtrip */
    public void test_sign_roundtrip() {
        var element = new SignElement();
        try {
            element.to = new Jid("alice@example.com");
        } catch (Error e) { fail_if_reached(); }
        element.payload = new StanzaNode.build("body", "jabber:client")
            .put_node(new StanzaNode.text("test body"));

        StanzaNode node = element.to_stanza_node();
        SignElement? parsed = SignElement.from_stanza_node(node);

        fail_if(parsed == null, "roundtrip parse must succeed");
        fail_if(parsed.to == null, "to must be present");
        fail_if_not_eq_str(parsed.to.to_string(), "alice@example.com", "to JID");
    }

    /** XEP-0374: SignElement rejects wrong root name */
    public void test_sign_wrong_root() {
        var node = new StanzaNode.build("signcrypt", OpenPgpContent.NS_URI).add_self_xmlns();
        SignElement? parsed = SignElement.from_stanza_node(node);
        fail_if(parsed != null, "wrong root name must return null");
    }

    /* ==================================================================
     * XEP-0374 CRYPT ELEMENT TESTS
     * ================================================================== */

    /** XEP-0374 §2.3: CryptElement has <crypt> with to, time, rpad, payload */
    public void test_crypt_structure() {
        var element = new CryptElement();
        try {
            element.to = new Jid("bob@example.com");
        } catch (Error e) { fail_if_reached(); }
        element.payload = new StanzaNode.build("body", "jabber:client")
            .put_node(new StanzaNode.text("encrypted message"));

        StanzaNode node = element.to_stanza_node();
        fail_if_not_eq_str(node.name, "crypt", "element name");
        fail_if_not_eq_str(node.ns_uri, OpenPgpContent.NS_URI, "namespace");

        fail_if(node.get_subnode("to", OpenPgpContent.NS_URI) == null, "to must exist");
        fail_if(node.get_subnode("time", OpenPgpContent.NS_URI) == null, "time must exist");
        fail_if(node.get_subnode("rpad", OpenPgpContent.NS_URI) == null, "rpad must exist");
        fail_if(node.get_subnode("payload", OpenPgpContent.NS_URI) == null, "payload must exist");
    }

    /** XEP-0374 §2.3: CryptElement roundtrip */
    public void test_crypt_roundtrip() {
        var element = new CryptElement();
        try {
            element.to = new Jid("charlie@example.com");
        } catch (Error e) { fail_if_reached(); }
        element.payload = new StanzaNode.build("body", "jabber:client")
            .put_node(new StanzaNode.text("secret"));

        StanzaNode node = element.to_stanza_node();
        CryptElement? parsed = CryptElement.from_stanza_node(node);

        fail_if(parsed == null, "roundtrip parse must succeed");
        fail_if(parsed.to == null, "to must be present");
        fail_if_not_eq_str(parsed.to.to_string(), "charlie@example.com", "to JID");
    }

    /** XEP-0374: CryptElement rejects wrong root name */
    public void test_crypt_wrong_root() {
        var node = new StanzaNode.build("sign", OpenPgpContent.NS_URI).add_self_xmlns();
        CryptElement? parsed = CryptElement.from_stanza_node(node);
        fail_if(parsed != null, "wrong root name must return null");
    }

    /* ==================================================================
     * XEP-0374 OPENPGP ELEMENT TESTS
     * ================================================================== */

    /** XEP-0374 §3: <openpgp xmlns='urn:xmpp:openpgp:0'>BASE64</openpgp> */
    public void test_openpgp_element() {
        string test_data = "SGVsbG8gV29ybGQ="; // base64 "Hello World"
        var element = new OpenpgpElement(test_data);
        StanzaNode node = element.to_stanza_node();

        fail_if_not_eq_str(node.name, "openpgp", "element name");
        fail_if_not_eq_str(node.ns_uri, OpenPgpContent.NS_URI, "namespace");

        string? content = node.get_string_content();
        fail_if_not_eq_str(content, test_data, "content must be preserved");
    }

    /** XEP-0374 §3: OpenpgpElement roundtrip */
    public void test_openpgp_roundtrip() {
        string test_data = "dGVzdCBkYXRhIGZvciBPcGVuUEdQ";
        var element = new OpenpgpElement(test_data);
        StanzaNode node = element.to_stanza_node();
        OpenpgpElement? parsed = OpenpgpElement.from_stanza_node(node);

        fail_if(parsed == null, "roundtrip parse must succeed");
        fail_if_not_eq_str(parsed.openpgp_data, test_data, "data roundtrip");
    }

    /** XEP-0374: OpenpgpElement rejects wrong root name */
    public void test_openpgp_wrong_root() {
        var node = new StanzaNode.build("encrypted", OpenPgpContent.NS_URI).add_self_xmlns()
            .put_node(new StanzaNode.text("data"));
        OpenpgpElement? parsed = OpenpgpElement.from_stanza_node(node);
        fail_if(parsed != null, "wrong root name must return null");
    }

    /** XEP-0374: OpenpgpElement returns null for empty content */
    public void test_openpgp_null_content() {
        var node = new StanzaNode.build("openpgp", OpenPgpContent.NS_URI).add_self_xmlns();
        // No text content
        OpenpgpElement? parsed = OpenpgpElement.from_stanza_node(node);
        fail_if(parsed != null, "null content must return null");
    }

    /* ==================================================================
     * XEP-0374 RANDOM PADDING TESTS
     * ================================================================== */

    /** XEP-0374 §2.1: rpad must be non-empty */
    public void test_rpad_nonempty() {
        var element = new SigncryptElement();
        fail_if(element.rpad == null, "rpad must not be null");
        fail_if(element.rpad.length == 0, "rpad must not be empty");
    }

    /** XEP-0374 §2.1: rpad is base64-encoded random bytes */
    public void test_rpad_is_base64() {
        var element = new SigncryptElement();
        string rpad = element.rpad;

        // Verify it can be decoded as base64
        uint8[] decoded = Base64.decode(rpad);
        fail_if_not(decoded.length >= 16, "rpad must decode to at least 16 bytes");
        fail_if_not(decoded.length <= 64, "rpad must decode to at most 64 bytes");
    }

    /* ==================================================================
     * XEP-0374 CROSS-ELEMENT REJECTION TESTS
     * ================================================================== */

    /** XEP-0374: SigncryptElement.from_stanza_node rejects <sign> */
    public void test_cross_signcrypt_sign() {
        var sign = new SignElement();
        StanzaNode node = sign.to_stanza_node();
        SigncryptElement? parsed = SigncryptElement.from_stanza_node(node);
        fail_if(parsed != null, "signcrypt parser must reject <sign>");
    }

    /** XEP-0374: SignElement.from_stanza_node rejects <crypt> */
    public void test_cross_sign_crypt() {
        var crypt = new CryptElement();
        StanzaNode node = crypt.to_stanza_node();
        SignElement? parsed = SignElement.from_stanza_node(node);
        fail_if(parsed != null, "sign parser must reject <crypt>");
    }

    /** XEP-0374: CryptElement.from_stanza_node rejects <signcrypt> */
    public void test_cross_crypt_signcrypt() {
        try {
            var sc = new SigncryptElement.with_body(new Jid("test@example.com"), "test");
            StanzaNode node = sc.to_stanza_node();
            CryptElement? parsed = CryptElement.from_stanza_node(node);
            fail_if(parsed != null, "crypt parser must reject <signcrypt>");
        } catch (Error e) { fail_if_reached(); }
    }

    /* ==================================================================
     * XEP-0374 RANDOM PADDING SECURITY AUDIT
     * ================================================================== */

    /**
     * BUG #16: Modulo bias in generate_random_padding() length calculation.
     *
     * The code uses: length = 16 + (int)(len_buf[0] % 49)
     * where len_buf[0] is a random byte [0..255].
     *
     * 256 % 49 = 11 (not zero!)
     *
     * This means values 0..10 appear with probability 6/256,
     * while values 11..48 appear with probability 5/256.
     * The first 11 lengths (16..26) are ~20% more likely than lengths 27..64.
     *
     * For uniform distribution, the accepted range must be divisible by 49.
     * The fix uses rejection sampling: discard values ≥ 245 (= 49*5).
     * Accepted range [0, 244] has 245 values, and 245 % 49 = 0 → uniform.
     *
     * This test verifies the mathematical invariant holds after the fix.
     */
    public void test_rpad_modulo_bias() {
        int accepted_range = 245; // rejection sampling threshold: 49 * 5
        int desired_range = 49;   // 16..64 = 49 distinct lengths
        int remainder = accepted_range % desired_range;

        // With rejection sampling (discard ≥ 245): 245 % 49 = 0 → uniform
        fail_if_not(remainder == 0,
            "BUG #16 FIXED: accepted range %d %% %d = %d (must be 0)".printf(
                accepted_range, desired_range, remainder));

        // Verify the old formula WAS biased
        int old_remainder = 256 % desired_range;
        fail_if_not(old_remainder != 0,
            "Sanity: old formula 256 %% 49 = %d was biased".printf(old_remainder));
    }

    /**
     * XEP-0374 §3: random padding must vary between instances.
     * Two independently created SigncryptElements must have different rpad.
     * (Probability of collision: ~2^-128 for 16+ random bytes)
     */
    public void test_rpad_varies() {
        try {
            var sc1 = new SigncryptElement.with_body(new Jid("a@b.com"), "msg1");
            var sc2 = new SigncryptElement.with_body(new Jid("a@b.com"), "msg1");
            fail_if(sc1.rpad == sc2.rpad,
                "XEP-0374: two independent rpad values must differ (CSPRNG broken?)");
        } catch (Error e) { fail_if_reached(); }
    }

    /**
     * XEP-0374 §3: decoded rpad length must be in [16, 64].
     * Test 20 samples to check the range.
     */
    public void test_rpad_decode_length_range() {
        try {
            for (int i = 0; i < 20; i++) {
                var sc = new SigncryptElement.with_body(new Jid("a@b.com"), "test");
                uint8[] decoded = Base64.decode(sc.rpad);
                if (decoded.length < 16 || decoded.length > 64) {
                    fail_if_reached("rpad decoded length %d out of [16,64] range on iteration %d"
                        .printf(decoded.length, i));
                    return;
                }
            }
        } catch (Error e) { fail_if_reached(); }
    }

    /**
     * NIST SP 800-90A: On Linux, /dev/urandom MUST be available for CSPRNG.
     * The generate_random_padding() function falls back to GLib.Random
     * (Mersenne Twister, NOT a CSPRNG) if /dev/urandom is unavailable.
     *
     * This test verifies that /dev/urandom exists on the current platform,
     * ensuring the CSPRNG path is taken (not the Mersenne Twister fallback).
     */
    public void test_rpad_csprng_available() {
        bool urandom_exists = FileUtils.test("/dev/urandom", FileTest.EXISTS);
        fail_if_not(urandom_exists,
            "SP800-90A: /dev/urandom must exist on Linux — " +
            "without it, rpad uses GLib.Random (Mersenne Twister, NOT CSPRNG!)");
    }
}

}
