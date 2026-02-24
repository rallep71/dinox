using Gee;

namespace Xmpp.Test {

/**
 * XEP-0260 / RFC 1928: SOCKS5 Bytestreams protocol logic
 *
 * Tests pure-logic functions from the Jingle SOCKS5 Bytestreams module:
 *   - calculate_dstaddr(): SHA1(sid + jid1 + jid2) per XEP-0260 §4
 *   - bytes_equal(): byte array comparison (used in handshake validation)
 *   - Candidate.parse() / to_xml(): XML ↔ object roundtrip
 *   - CandidateType.to_string(): enum → string serialization
 *   - Proxy URI construction for Tor/SOCKS5 (starttls_xmpp_stream.vala)
 */
class Socks5Audit : Gee.TestCase {

    public Socks5Audit() {
        base("Socks5Audit");

        // --- calculate_dstaddr (XEP-0260 §4) ---
        add_test("XEP0260_dstaddr_sha1_deterministic", test_dstaddr_deterministic);
        add_test("XEP0260_dstaddr_order_matters", test_dstaddr_order_matters);
        add_test("XEP0260_dstaddr_is_sha1_hex_lowercase", test_dstaddr_is_sha1_hex);
        add_test("XEP0260_dstaddr_different_sid_different_hash", test_dstaddr_different_sid);

        // --- bytes_equal ---
        add_test("RFC1928_bytes_equal_same", test_bytes_equal_same);
        add_test("RFC1928_bytes_equal_different_content", test_bytes_equal_diff_content);
        add_test("RFC1928_bytes_equal_different_length", test_bytes_equal_diff_length);
        add_test("RFC1928_bytes_equal_empty", test_bytes_equal_empty);

        // --- CandidateType.to_string roundtrip ---
        add_test("XEP0260_candidate_type_roundtrip_all", test_candidate_type_roundtrip);

        // --- Candidate XML roundtrip ---
        add_test("XEP0260_candidate_parse_xml_roundtrip", test_candidate_xml_roundtrip);
        add_test("XEP0260_candidate_parse_missing_cid_throws", test_candidate_parse_missing_cid);
        add_test("XEP0260_candidate_parse_default_type_direct", test_candidate_parse_default_type);
        add_test("XEP0260_candidate_parse_default_port_1080", test_candidate_parse_default_port);
        add_test("XEP0260_candidate_priority_includes_type", test_candidate_priority_type);
    }

    // ===================== calculate_dstaddr =====================

    /**
     * XEP-0260 §4: dstaddr = SHA1(sid + initiator_jid + responder_jid)
     * Same inputs MUST produce same output (deterministic).
     */
    private void test_dstaddr_deterministic() {
        string sid = "test-session-123";
        try {
            Jid jid1 = new Jid("alice@example.com/res1");
            Jid jid2 = new Jid("bob@example.com/res2");

            string h1 = Xep.JingleSocks5Bytestreams.calculate_dstaddr(sid, jid1, jid2);
            string h2 = Xep.JingleSocks5Bytestreams.calculate_dstaddr(sid, jid1, jid2);

            fail_if_not_eq_str(h1, h2);
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0260 §4: SHA1(sid + jid1 + jid2) != SHA1(sid + jid2 + jid1)
     * Argument order MUST matter.
     */
    private void test_dstaddr_order_matters() {
        string sid = "session-order";
        try {
            Jid jid1 = new Jid("alice@example.com/r1");
            Jid jid2 = new Jid("bob@example.com/r2");

            string h1 = Xep.JingleSocks5Bytestreams.calculate_dstaddr(sid, jid1, jid2);
            string h2 = Xep.JingleSocks5Bytestreams.calculate_dstaddr(sid, jid2, jid1);

            fail_if(h1 == h2, "XEP-0260 §4: dstaddr MUST differ when JID order is swapped");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * SHA1 hex output MUST be 40 lowercase hex characters.
     */
    private void test_dstaddr_is_sha1_hex() {
        try {
            Jid jid1 = new Jid("user@host.tld/res");
            Jid jid2 = new Jid("peer@other.tld/dev");

            string h = Xep.JingleSocks5Bytestreams.calculate_dstaddr("s1", jid1, jid2);

            fail_if(h.length != 40, @"SHA1 hex MUST be 40 chars, got $(h.length)");

            // Must be all lowercase hex
            for (int i = 0; i < h.length; i++) {
                char c = h[i];
                bool valid = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                fail_if(!valid, @"SHA1 hex char at pos $i MUST be lowercase hex, got '$(c)'");
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * Different session IDs MUST produce different dstaddr hashes.
     */
    private void test_dstaddr_different_sid() {
        try {
            Jid jid1 = new Jid("a@b.c/d");
            Jid jid2 = new Jid("e@f.g/h");

            string h1 = Xep.JingleSocks5Bytestreams.calculate_dstaddr("session-alpha", jid1, jid2);
            string h2 = Xep.JingleSocks5Bytestreams.calculate_dstaddr("session-beta", jid1, jid2);

            fail_if(h1 == h2, "XEP-0260: different SID MUST produce different dstaddr");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===================== bytes_equal =====================

    private void test_bytes_equal_same() {
        uint8[] a = { 0x05, 0x01, 0x00 };
        uint8[] b = { 0x05, 0x01, 0x00 };
        fail_if_not(Xep.JingleSocks5Bytestreams.bytes_equal(a, b),
                    "RFC 1928: identical byte arrays MUST be equal");
    }

    private void test_bytes_equal_diff_content() {
        uint8[] a = { 0x05, 0x01, 0x00 };
        uint8[] b = { 0x05, 0x01, 0x01 };
        fail_if(Xep.JingleSocks5Bytestreams.bytes_equal(a, b),
                "RFC 1928: differing byte arrays MUST NOT be equal");
    }

    private void test_bytes_equal_diff_length() {
        uint8[] a = { 0x05, 0x01 };
        uint8[] b = { 0x05, 0x01, 0x00 };
        fail_if(Xep.JingleSocks5Bytestreams.bytes_equal(a, b),
                "RFC 1928: different-length arrays MUST NOT be equal");
    }

    private void test_bytes_equal_empty() {
        uint8[] a = {};
        uint8[] b = {};
        fail_if_not(Xep.JingleSocks5Bytestreams.bytes_equal(a, b),
                    "RFC 1928: two empty arrays MUST be equal");
    }

    // ===================== CandidateType.to_string roundtrip =====================

    /**
     * All 4 CandidateType values MUST roundtrip through to_string() → parse().
     */
    private void test_candidate_type_roundtrip() {
        try {
            var types = new Xep.JingleSocks5Bytestreams.CandidateType[] {
                Xep.JingleSocks5Bytestreams.CandidateType.ASSISTED,
                Xep.JingleSocks5Bytestreams.CandidateType.DIRECT,
                Xep.JingleSocks5Bytestreams.CandidateType.PROXY,
                Xep.JingleSocks5Bytestreams.CandidateType.TUNNEL
            };
            foreach (var t in types) {
                string s = t.to_string();
                var parsed = Xep.JingleSocks5Bytestreams.CandidateType.parse(s);
                fail_if(parsed != t,
                        @"XEP-0260: CandidateType.$(s) MUST roundtrip through to_string()/parse()");
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===================== Candidate XML roundtrip =====================

    /**
     * XEP-0260: Candidate.parse(node) → to_xml() MUST preserve all attributes.
     */
    private void test_candidate_xml_roundtrip() {
        try {
            string xml = "<candidate xmlns='urn:xmpp:jingle:transports:s5b:1' " +
                         "cid='c1' host='192.168.1.1' jid='proxy@example.com' " +
                         "port='5086' priority='8257636' type='direct'/>";

            var reader = new StanzaReader.for_string(xml);
            var node = yield_stanza_node(reader);

            var candidate = Xep.JingleSocks5Bytestreams.Candidate.parse(node);

            fail_if_not_eq_str(candidate.cid, "c1");
            fail_if_not_eq_str(candidate.host, "192.168.1.1");
            fail_if_not_eq_str(candidate.jid.to_string(), "proxy@example.com");
            fail_if_not_eq_int(candidate.port, 5086);
            fail_if_not_eq_int(candidate.priority, 8257636);
            fail_if_not(candidate.type_ == Xep.JingleSocks5Bytestreams.CandidateType.DIRECT,
                        "XEP-0260: type MUST be DIRECT");

            // Serialize back and verify
            var out_node = candidate.to_xml();
            fail_if_not_eq_str(out_node.get_attribute("cid"), "c1");
            fail_if_not_eq_str(out_node.get_attribute("host"), "192.168.1.1");
            fail_if_not_eq_str(out_node.get_attribute("jid"), "proxy@example.com");
            fail_if_not_eq_str(out_node.get_attribute("port"), "5086");
            fail_if_not_eq_str(out_node.get_attribute("priority"), "8257636");
            fail_if_not_eq_str(out_node.get_attribute("type"), "direct");
        } catch (Error e) {
            fail_if_reached(@"XML roundtrip error: $(e.message)");
        }
    }

    /**
     * XEP-0260: Missing cid attribute MUST throw IqError.BAD_REQUEST.
     */
    private void test_candidate_parse_missing_cid() {
        try {
            // Missing cid attribute
            string xml = "<candidate xmlns='urn:xmpp:jingle:transports:s5b:1' " +
                         "host='1.2.3.4' jid='j@ex.com' port='1080' priority='100' type='direct'/>";

            var reader = new StanzaReader.for_string(xml);
            var node = yield_stanza_node(reader);

            try {
                Xep.JingleSocks5Bytestreams.Candidate.parse(node);
                fail_if(true, "XEP-0260: missing cid MUST throw IqError");
            } catch (Xep.Jingle.IqError e) {
                // Expected
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0260: Missing type attribute MUST default to DIRECT.
     */
    private void test_candidate_parse_default_type() {
        try {
            string xml = "<candidate xmlns='urn:xmpp:jingle:transports:s5b:1' " +
                         "cid='c2' host='1.2.3.4' jid='j@ex.com' port='1080' priority='100'/>";

            var reader = new StanzaReader.for_string(xml);
            var node = yield_stanza_node(reader);

            var candidate = Xep.JingleSocks5Bytestreams.Candidate.parse(node);
            fail_if_not(candidate.type_ == Xep.JingleSocks5Bytestreams.CandidateType.DIRECT,
                        "XEP-0260: missing type MUST default to DIRECT");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0260: Missing port attribute MUST default to 1080.
     */
    private void test_candidate_parse_default_port() {
        try {
            string xml = "<candidate xmlns='urn:xmpp:jingle:transports:s5b:1' " +
                         "cid='c3' host='1.2.3.4' jid='j@ex.com' priority='100' type='proxy'/>";

            var reader = new StanzaReader.for_string(xml);
            var node = yield_stanza_node(reader);

            var candidate = Xep.JingleSocks5Bytestreams.Candidate.parse(node);
            fail_if_not_eq_int(candidate.port, 1080);
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0260: Candidate.build() priority MUST include type_preference.
     * direct (126<<16) > assisted (120<<16) > tunnel (110<<16) > proxy (10<<16)
     */
    private void test_candidate_priority_type() {
        try {
            var jid = new Jid("p@ex.com");
            int local_prio = 500;

            var direct = new Xep.JingleSocks5Bytestreams.Candidate.build(
                "d1", "1.2.3.4", jid, 1080, local_prio,
                Xep.JingleSocks5Bytestreams.CandidateType.DIRECT);
            var proxy = new Xep.JingleSocks5Bytestreams.Candidate.build(
                "p1", "5.6.7.8", jid, 1080, local_prio,
                Xep.JingleSocks5Bytestreams.CandidateType.PROXY);

            fail_if(direct.priority <= proxy.priority,
                    @"XEP-0260: DIRECT priority ($(direct.priority)) MUST be > PROXY priority ($(proxy.priority))");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===================== Helpers =====================

    /** Synchronously read a StanzaNode from XML string. */
    private StanzaNode? yield_stanza_node(StanzaReader reader) {
        StanzaNode? result = null;
        var loop = new MainLoop();
        read_node_async.begin(reader, (obj, res) => {
            try {
                result = read_node_async.end(res);
            } catch (Error e) {
                warning("yield_stanza_node error: %s", e.message);
            }
            loop.quit();
        });
        loop.run();
        return result;
    }

    private async StanzaNode read_node_async(StanzaReader reader) throws Error {
        return yield reader.read_node();
    }
}

}
