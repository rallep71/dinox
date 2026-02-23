using Gee;

namespace Xmpp.Test {

/**
 * Security Audit: Protocol enum parsers
 *
 * Tests pure-logic enum parsers that process untrusted input from
 * incoming XMPP stanzas. Each parser takes a string and returns an
 * enum value or throws IqError. Incorrect parsing can lead to
 * connection denial or unexpected behavior.
 *
 * Covers:
 *   - XEP-0166 Jingle Senders.parse / Role.parse
 *   - XEP-0260 SOCKS5 CandidateType.parse / type_preference
 *   - XEP-0176 ICE-UDP Candidate.Type.parse
 *   - XEP-0394 MessageMarkup span_type_to_str / str_to_span_type
 *   - XEP-0082 DateTimeProfiles parse_string / to_datetime
 */
class ProtocolParserAudit : Gee.TestCase {

    public ProtocolParserAudit() {
        base("ProtocolParserAudit");

        // --- Jingle Senders ---
        add_test("XEP0166_senders_parse_initiator", test_senders_initiator);
        add_test("XEP0166_senders_parse_responder", test_senders_responder);
        add_test("XEP0166_senders_parse_both", test_senders_both);
        add_test("XEP0166_senders_parse_null_defaults_both", test_senders_null);
        add_test("XEP0166_senders_parse_invalid_throws", test_senders_invalid);
        add_test("XEP0166_senders_parse_none_throws", test_senders_none);

        // --- Jingle Role ---
        add_test("XEP0166_role_parse_initiator", test_role_initiator);
        add_test("XEP0166_role_parse_responder", test_role_responder);
        add_test("XEP0166_role_parse_invalid_throws", test_role_invalid);

        // --- SOCKS5 CandidateType ---
        add_test("XEP0260_candidate_parse_assisted", test_s5_assisted);
        add_test("XEP0260_candidate_parse_direct", test_s5_direct);
        add_test("XEP0260_candidate_parse_proxy", test_s5_proxy);
        add_test("XEP0260_candidate_parse_tunnel", test_s5_tunnel);
        add_test("XEP0260_candidate_parse_invalid_throws", test_s5_invalid);
        add_test("XEP0260_type_preference_ordering", test_s5_preference_order);

        // --- ICE-UDP Type ---
        add_test("XEP0176_ice_type_host", test_ice_host);
        add_test("XEP0176_ice_type_srflx", test_ice_srflx);
        add_test("XEP0176_ice_type_relay", test_ice_relay);
        add_test("XEP0176_ice_type_prflx", test_ice_prflx);
        add_test("XEP0176_ice_type_invalid_throws", test_ice_invalid);

        // --- MessageMarkup ---
        add_test("XEP0394_span_emphasis_roundtrip", test_markup_emphasis);
        add_test("XEP0394_span_strong_roundtrip", test_markup_strong);
        add_test("XEP0394_span_deleted_roundtrip", test_markup_deleted);
        add_test("XEP0394_span_unknown_defaults_emphasis", test_markup_unknown);

        // --- DateTimeProfiles ---
        add_test("XEP0082_parse_valid_iso8601", test_dt_valid);
        add_test("XEP0082_parse_invalid_returns_null", test_dt_invalid);
        add_test("XEP0082_roundtrip", test_dt_roundtrip);
    }

    // ===================== Jingle Senders =====================

    private void test_senders_initiator() {
        try {
            var s = Xep.Jingle.Senders.parse("initiator");
            fail_if_not(s == Xep.Jingle.Senders.INITIATOR, "should be INITIATOR");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_senders_responder() {
        try {
            var s = Xep.Jingle.Senders.parse("responder");
            fail_if_not(s == Xep.Jingle.Senders.RESPONDER, "should be RESPONDER");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_senders_both() {
        try {
            var s = Xep.Jingle.Senders.parse("both");
            fail_if_not(s == Xep.Jingle.Senders.BOTH, "should be BOTH");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_senders_null() {
        try {
            var s = Xep.Jingle.Senders.parse(null);
            fail_if_not(s == Xep.Jingle.Senders.BOTH, "null should default to BOTH");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"null should not throw: $(e.message)");
        }
    }

    private void test_senders_invalid() {
        try {
            Xep.Jingle.Senders.parse("invalid");
            fail_if_reached("Invalid senders should throw IqError");
        } catch (Xep.Jingle.IqError e) {
            // Expected
        }
    }

    private void test_senders_none() {
        // "none" is a valid enum member in Senders but NOT handled by parse()
        try {
            Xep.Jingle.Senders.parse("none");
            fail_if_reached("'none' should throw IqError (not in parse switch)");
        } catch (Xep.Jingle.IqError e) {
            // Expected - "none" is valid enum but not accepted via parsing
        }
    }

    // ===================== Jingle Role =====================

    private void test_role_initiator() {
        try {
            var r = Xep.Jingle.Role.parse("initiator");
            fail_if_not(r == Xep.Jingle.Role.INITIATOR, "should be INITIATOR");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_role_responder() {
        try {
            var r = Xep.Jingle.Role.parse("responder");
            fail_if_not(r == Xep.Jingle.Role.RESPONDER, "should be RESPONDER");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_role_invalid() {
        try {
            Xep.Jingle.Role.parse("unknown");
            fail_if_reached("Invalid role should throw IqError");
        } catch (Xep.Jingle.IqError e) {
            // Expected
        }
    }

    // ===================== SOCKS5 CandidateType =====================

    private void test_s5_assisted() {
        try {
            var t = Xep.JingleSocks5Bytestreams.CandidateType.parse("assisted");
            fail_if_not(t == Xep.JingleSocks5Bytestreams.CandidateType.ASSISTED, "should be ASSISTED");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_s5_direct() {
        try {
            var t = Xep.JingleSocks5Bytestreams.CandidateType.parse("direct");
            fail_if_not(t == Xep.JingleSocks5Bytestreams.CandidateType.DIRECT, "should be DIRECT");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_s5_proxy() {
        try {
            var t = Xep.JingleSocks5Bytestreams.CandidateType.parse("proxy");
            fail_if_not(t == Xep.JingleSocks5Bytestreams.CandidateType.PROXY, "should be PROXY");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_s5_tunnel() {
        try {
            var t = Xep.JingleSocks5Bytestreams.CandidateType.parse("tunnel");
            fail_if_not(t == Xep.JingleSocks5Bytestreams.CandidateType.TUNNEL, "should be TUNNEL");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_s5_invalid() {
        try {
            Xep.JingleSocks5Bytestreams.CandidateType.parse("unknown");
            fail_if_reached("Invalid candidate type should throw IqError");
        } catch (Xep.Jingle.IqError e) {
            // Expected
        }
    }

    private void test_s5_preference_order() {
        // Per XEP-0260: direct > assisted > tunnel > proxy
        int pref_direct = Xep.JingleSocks5Bytestreams.CandidateType.DIRECT.type_preference();
        int pref_assisted = Xep.JingleSocks5Bytestreams.CandidateType.ASSISTED.type_preference();
        int pref_tunnel = Xep.JingleSocks5Bytestreams.CandidateType.TUNNEL.type_preference();
        int pref_proxy = Xep.JingleSocks5Bytestreams.CandidateType.PROXY.type_preference();

        fail_if_not(pref_direct > pref_assisted,
            @"direct ($pref_direct) should have higher preference than assisted ($pref_assisted)");
        fail_if_not(pref_assisted > pref_tunnel,
            @"assisted ($pref_assisted) should have higher preference than tunnel ($pref_tunnel)");
        fail_if_not(pref_tunnel > pref_proxy,
            @"tunnel ($pref_tunnel) should have higher preference than proxy ($pref_proxy)");
    }

    // ===================== ICE-UDP Type =====================

    private void test_ice_host() {
        try {
            var t = Xep.JingleIceUdp.Candidate.Type.parse("host");
            fail_if_not(t == Xep.JingleIceUdp.Candidate.Type.HOST, "should be HOST");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_ice_srflx() {
        try {
            var t = Xep.JingleIceUdp.Candidate.Type.parse("srflx");
            fail_if_not(t == Xep.JingleIceUdp.Candidate.Type.SRFLX, "should be SRFLX");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_ice_relay() {
        try {
            var t = Xep.JingleIceUdp.Candidate.Type.parse("relay");
            fail_if_not(t == Xep.JingleIceUdp.Candidate.Type.RELAY, "should be RELAY");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_ice_prflx() {
        try {
            var t = Xep.JingleIceUdp.Candidate.Type.parse("prflx");
            fail_if_not(t == Xep.JingleIceUdp.Candidate.Type.PRFLX, "should be PRFLX");
        } catch (Xep.Jingle.IqError e) {
            fail_if_reached(@"Should not throw: $(e.message)");
        }
    }

    private void test_ice_invalid() {
        try {
            Xep.JingleIceUdp.Candidate.Type.parse("unknown");
            fail_if_reached("Invalid ICE type should throw IqError");
        } catch (Xep.Jingle.IqError e) {
            // Expected
        }
    }

    // ===================== MessageMarkup =====================

    private void test_markup_emphasis() {
        string s = Xep.MessageMarkup.span_type_to_str(Xep.MessageMarkup.SpanType.EMPHASIS);
        fail_if_not_eq_str(s, "emphasis", "EMPHASIS → 'emphasis'");
        var rt = Xep.MessageMarkup.str_to_span_type("emphasis");
        fail_if_not(rt == Xep.MessageMarkup.SpanType.EMPHASIS, "'emphasis' → EMPHASIS");
    }

    private void test_markup_strong() {
        string s = Xep.MessageMarkup.span_type_to_str(Xep.MessageMarkup.SpanType.STRONG_EMPHASIS);
        fail_if_not_eq_str(s, "strong", "STRONG_EMPHASIS → 'strong'");
        var rt = Xep.MessageMarkup.str_to_span_type("strong");
        fail_if_not(rt == Xep.MessageMarkup.SpanType.STRONG_EMPHASIS, "'strong' → STRONG_EMPHASIS");
    }

    private void test_markup_deleted() {
        string s = Xep.MessageMarkup.span_type_to_str(Xep.MessageMarkup.SpanType.DELETED);
        fail_if_not_eq_str(s, "deleted", "DELETED → 'deleted'");
        var rt = Xep.MessageMarkup.str_to_span_type("deleted");
        fail_if_not(rt == Xep.MessageMarkup.SpanType.DELETED, "'deleted' → DELETED");
    }

    private void test_markup_unknown() {
        // Unknown strings silently default to EMPHASIS
        var t = Xep.MessageMarkup.str_to_span_type("underline");
        fail_if_not(t == Xep.MessageMarkup.SpanType.EMPHASIS,
            "Unknown span type should default to EMPHASIS");
    }

    // ===================== DateTimeProfiles =====================

    private void test_dt_valid() {
        DateTime? dt = Xep.DateTimeProfiles.parse_string("2023-06-15T12:30:00Z");
        fail_if(dt == null, "Valid ISO 8601 string should parse to non-null DateTime");
        if (dt != null) {
            fail_if_not_eq_int(dt.get_year(), 2023, "year should be 2023");
            fail_if_not_eq_int(dt.get_month(), 6, "month should be 6");
            fail_if_not_eq_int(dt.get_day_of_month(), 15, "day should be 15");
        }
    }

    private void test_dt_invalid() {
        DateTime? dt = Xep.DateTimeProfiles.parse_string("not-a-date");
        fail_if(dt != null, "Invalid date string should return null");
    }

    private void test_dt_roundtrip() {
        var now = new DateTime.now_utc();
        string formatted = Xep.DateTimeProfiles.to_datetime(now);
        DateTime? parsed = Xep.DateTimeProfiles.parse_string(formatted);
        fail_if(parsed == null, "Formatted datetime should parse back");
        if (parsed != null) {
            // Compare to second precision (formatting may truncate microseconds)
            fail_if_not_eq_int(now.get_year(), parsed.get_year(), "roundtrip year");
            fail_if_not_eq_int(now.get_month(), parsed.get_month(), "roundtrip month");
            fail_if_not_eq_int(now.get_day_of_month(), parsed.get_day_of_month(), "roundtrip day");
            fail_if_not_eq_int(now.get_hour(), parsed.get_hour(), "roundtrip hour");
            fail_if_not_eq_int(now.get_minute(), parsed.get_minute(), "roundtrip minute");
            fail_if_not_eq_int(now.get_second(), parsed.get_second(), "roundtrip second");
        }
    }
}

}
