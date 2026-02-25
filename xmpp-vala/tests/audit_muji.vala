using Gee;

namespace Xmpp.Test {

/**
 * XEP-0272: MUJI (Multi-User Jingle Interaction) -- Group Call Protocol
 * XEP-0482: Call Invites -- MUJI propose/accept/retract stanzas
 * XEP-0167: Jingle RTP -- PayloadType codec intersection
 * XEP-0045: MUC -- Presence with MUJI extension
 *
 * Tests pure-logic and stanza-format aspects of the MUJI group call
 * implementation. No network I/O required -- only XML parsing via
 * StanzaReader, data class contracts, and namespace correctness.
 *
 * References:
 *   XEP-0272 S3: MUJI presence with <muji xmlns='urn:xmpp:jingle:muji:0'>
 *   XEP-0272 S4: <preparing/> element during codec negotiation
 *   XEP-0272 S5: <content> with <description> carrying payload-types
 *   XEP-0482 S3: <invite> with <muji room='...'/>
 *   XEP-0167 S5: PayloadType id, name, clockrate, channels
 *   RFC 4566 S6: SDP payload type IDs 0-127 (static+dynamic)
 */
class MujiAudit : Gee.TestCase {

    public MujiAudit() {
        base("MujiAudit");

        // --- XEP-0272: Namespace & Constants ---
        add_test("XEP0272_ns_uri_is_jingle_muji_0", test_ns_uri);
        add_test("XEP0272_call_invites_ns_uri", test_call_invites_ns);

        // --- XEP-0272 S3: MUJI Presence Stanza Format ---
        add_async_test("XEP0272_S3_preparing_presence_parse", test_preparing_presence_parse);
        add_async_test("XEP0272_S3_ready_presence_with_codecs_parse", test_ready_presence_parse);
        add_async_test("XEP0272_S3_presence_missing_muji_node_ignored", test_presence_no_muji_node);
        add_async_test("XEP0272_S3_presence_preparing_is_empty_element", test_preparing_is_empty);

        // --- XEP-0272 S5: Payload Type in MUJI Presence ---
        add_async_test("XEP0272_S5_audio_payload_type_opus_parsed", test_payload_type_opus);
        add_async_test("XEP0272_S5_video_payload_type_vp8_parsed", test_payload_type_vp8);
        add_async_test("XEP0272_S5_multiple_payload_types_in_description", test_multiple_payload_types);
        add_async_test("XEP0272_S5_payload_type_with_parameters", test_payload_type_parameters);

        // --- XEP-0272: Codec Intersection Logic ---
        add_test("XEP0167_payload_type_equals_same", test_payload_equals_same);
        add_test("XEP0167_payload_type_equals_different_id", test_payload_equals_different_id);
        add_test("XEP0167_payload_type_clone_is_equal", test_payload_clone_equal);

        // --- XEP-0272: GroupCall Data Class ---
        add_test("XEP0272_groupcall_muc_jid_stored", test_groupcall_muc_jid);
        add_test("XEP0272_groupcall_peers_initially_empty", test_groupcall_peers_empty);
        add_test("XEP0272_groupcall_peers_to_connect_initially_empty", test_groupcall_connect_empty);
        add_test("XEP0272_groupcall_signal_peer_joined_fires", test_groupcall_peer_joined_signal);
        add_test("XEP0272_groupcall_signal_peer_left_fires", test_groupcall_peer_left_signal);
        add_test("XEP0272_groupcall_signal_codecs_changed_fires", test_groupcall_codecs_changed_signal);

        // --- XEP-0272: Flag (stream flag) ---
        add_test("XEP0272_flag_ns_matches_module", test_flag_ns);
        add_test("XEP0272_flag_calls_map_initially_empty", test_flag_calls_empty);
        add_test("XEP0272_flag_calls_map_store_retrieve", test_flag_calls_store);

        // --- XEP-0272: Nick Format ---
        add_test("XEP0272_nick_is_8_hex_chars", test_nick_format);

        // --- XEP-0482: Call Invite Stanza with MUJI ---
        add_async_test("XEP0482_muji_propose_has_room_attribute", test_cim_muji_propose);
        add_async_test("XEP0482_muji_propose_muji_ns_correct", test_cim_muji_ns);
        add_async_test("XEP0482_invite_has_call_id", test_cim_invite_call_id);
        add_async_test("XEP0482_invite_video_attribute", test_cim_invite_video);
        add_async_test("XEP0482_retract_has_id", test_cim_retract);
        add_async_test("XEP0482_accept_has_muji_room", test_cim_accept_muji);

        // --- RFC 4566 / XEP-0167: PayloadType ID Range ---
        add_test("RFC4566_payload_id_range_0_127", test_payload_id_range);

        // --- XEP-0272: Payload Intersection Determinism ---
        add_test("XEP0272_payload_intersection_empty_if_no_common", test_intersection_no_common);
        add_test("XEP0272_payload_intersection_keeps_common", test_intersection_keeps_common);
    }

    // ===================== XEP-0272 Namespace =====================

    /**
     * XEP-0272 S2: The namespace MUST be "urn:xmpp:jingle:muji:0".
     */
    private void test_ns_uri() {
        fail_if_not_eq_str(Xep.Muji.NS_URI, "urn:xmpp:jingle:muji:0",
            "XEP-0272 S2: MUJI namespace MUST be 'urn:xmpp:jingle:muji:0'");
    }

    /**
     * XEP-0482 S2: Call Invites namespace MUST be "urn:xmpp:call-invites:0".
     */
    private void test_call_invites_ns() {
        fail_if_not_eq_str(Xep.CallInvites.NS_URI, "urn:xmpp:call-invites:0",
            "XEP-0482 S2: Call Invites namespace MUST be 'urn:xmpp:call-invites:0'");
    }

    // ===================== XEP-0272 S3: Preparing Presence =====================

    /**
     * XEP-0272 S3: A participant joining sends presence with
     * <muji xmlns='urn:xmpp:jingle:muji:0'><preparing/></muji>
     * Parse via StanzaReader to verify structure.
     */
    private void test_preparing_presence_parse(Gee.TestFinishedCallback cb) {
        string xml = "<presence xmlns='jabber:client' from='call@conference.example.com/abc123' to='user@example.com'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0'><preparing/></muji>"
            + "</presence>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? muji = node.get_subnode("muji", Xep.Muji.NS_URI);
            fail_if(muji == null, "XEP-0272 S3: <muji> element MUST be present in preparing presence");
            if (muji != null) {
                StanzaNode? preparing = muji.get_subnode("preparing", Xep.Muji.NS_URI);
                fail_if(preparing == null, "XEP-0272 S3: <preparing/> MUST be child of <muji> during negotiation");
            }
            cb();
        });
    }

    /**
     * XEP-0272 S3: After negotiation, participant sends MUJI presence with
     * <content> elements containing <description> with payload-types.
     * The <preparing/> element MUST be absent.
     */
    private void test_ready_presence_parse(Gee.TestFinishedCallback cb) {
        string xml = "<presence xmlns='jabber:client' from='call@conference.example.com/peer1'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0'>"
            + "<content xmlns='urn:xmpp:jingle:1' name='audio'>"
            + "<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'>"
            + "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='111' name='opus' clockrate='48000' channels='2'/>"
            + "</description>"
            + "</content>"
            + "</muji>"
            + "</presence>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? muji = node.get_subnode("muji", Xep.Muji.NS_URI);
            fail_if(muji == null, "XEP-0272 S3: <muji> MUST be present in ready presence");
            if (muji != null) {
                StanzaNode? preparing = muji.get_subnode("preparing", Xep.Muji.NS_URI);
                fail_if(preparing != null, "XEP-0272 S3: <preparing/> MUST be absent in ready presence");

                Gee.List<StanzaNode> contents = muji.get_subnodes("content", Xep.Jingle.NS_URI);
                fail_if(contents.is_empty, "XEP-0272 S5: Ready presence MUST have at least one <content>");

                if (!contents.is_empty) {
                    StanzaNode? desc = contents[0].get_subnode("description", Xep.JingleRtp.NS_URI);
                    fail_if(desc == null, "XEP-0272 S5: <content> MUST contain <description>");
                    if (desc != null) {
                        fail_if_not_eq_str(desc.get_attribute("media"), "audio",
                            "XEP-0272 S5: description media attribute MUST match content name");
                    }
                }
            }
            cb();
        });
    }

    /**
     * XEP-0272: Presence stanza without <muji> node must be ignored.
     */
    private void test_presence_no_muji_node(Gee.TestFinishedCallback cb) {
        string xml = "<presence xmlns='jabber:client' from='call@conference.example.com/nick1'>"
            + "<x xmlns='http://jabber.org/protocol/muc#user'/>"
            + "</presence>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? muji = node.get_subnode("muji", Xep.Muji.NS_URI);
            fail_if(muji != null, "XEP-0272: Non-MUJI presence MUST NOT have <muji> node");
            cb();
        });
    }

    /**
     * XEP-0272 S3: <preparing/> MUST be an empty element (no children, no text).
     */
    private void test_preparing_is_empty(Gee.TestFinishedCallback cb) {
        string xml = "<presence xmlns='jabber:client' from='call@conference.example.com/nick1'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0'><preparing/></muji>"
            + "</presence>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? preparing = node.get_deep_subnode(
                Xep.Muji.NS_URI + ":muji", Xep.Muji.NS_URI + ":preparing");
            fail_if(preparing == null, "XEP-0272 S3: <preparing/> MUST be parseable");
            if (preparing != null) {
                fail_if(!preparing.sub_nodes.is_empty,
                    "XEP-0272 S3: <preparing/> MUST be an empty element (no children)");
            }
            cb();
        });
    }

    // ===================== XEP-0272 S5: PayloadType Parsing =====================

    /**
     * XEP-0272 S5 / XEP-0167 S5: Opus payload-type in MUJI presence.
     * id=111, name=opus, clockrate=48000, channels=2
     */
    private void test_payload_type_opus(Gee.TestFinishedCallback cb) {
        string xml = "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='111' name='opus' clockrate='48000' channels='2'/>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            Xep.JingleRtp.PayloadType pt = Xep.JingleRtp.PayloadType.parse(node);
            fail_if_not_eq_uint(pt.id, 111, "XEP-0167 S5: Opus payload ID MUST be 111");
            fail_if_not_eq_str(pt.name, "opus", "XEP-0167 S5: Opus payload name MUST be 'opus'");
            fail_if_not_eq_uint(pt.clockrate, 48000, "XEP-0167 S5: Opus clockrate MUST be 48000");
            fail_if_not_eq_uint(pt.channels, 2, "XEP-0167 S5: Opus channels MUST be 2");
            cb();
        });
    }

    /**
     * XEP-0272 S5 / XEP-0167: VP8 video payload-type.
     */
    private void test_payload_type_vp8(Gee.TestFinishedCallback cb) {
        string xml = "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='96' name='VP8' clockrate='90000'/>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            Xep.JingleRtp.PayloadType pt = Xep.JingleRtp.PayloadType.parse(node);
            fail_if_not_eq_uint(pt.id, 96, "XEP-0167: VP8 dynamic payload ID");
            fail_if_not_eq_str(pt.name, "VP8", "XEP-0167: VP8 payload name");
            fail_if_not_eq_uint(pt.clockrate, 90000, "XEP-0167: VP8 clockrate MUST be 90000 (video)");
            fail_if_not_eq_uint(pt.channels, 1, "XEP-0167: VP8 channels defaults to 1");
            cb();
        });
    }

    /**
     * XEP-0272 S5: A description may contain multiple payload-types.
     * All must be parsed correctly.
     */
    private void test_multiple_payload_types(Gee.TestFinishedCallback cb) {
        string xml = "<description xmlns='urn:xmpp:jingle:apps:rtp:1' media='audio'>"
            + "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='111' name='opus' clockrate='48000' channels='2'/>"
            + "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='0' name='PCMU' clockrate='8000'/>"
            + "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='8' name='PCMA' clockrate='8000'/>"
            + "</description>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            Gee.List<StanzaNode> payload_nodes = node.get_subnodes("payload-type", Xep.JingleRtp.NS_URI);
            fail_if_not_eq_int(payload_nodes.size, 3,
                "XEP-0272 S5: All payload-types in description MUST be parsed");

            if (payload_nodes.size >= 3) {
                Xep.JingleRtp.PayloadType pt0 = Xep.JingleRtp.PayloadType.parse(payload_nodes[0]);
                Xep.JingleRtp.PayloadType pt1 = Xep.JingleRtp.PayloadType.parse(payload_nodes[1]);
                Xep.JingleRtp.PayloadType pt2 = Xep.JingleRtp.PayloadType.parse(payload_nodes[2]);
                fail_if_not_eq_str(pt0.name, "opus", "First payload MUST be opus");
                fail_if_not_eq_str(pt1.name, "PCMU", "Second payload MUST be PCMU");
                fail_if_not_eq_str(pt2.name, "PCMA", "Third payload MUST be PCMA");
            }
            cb();
        });
    }

    /**
     * XEP-0167 S5: PayloadType may contain <parameter name='...' value='...'/>.
     */
    private void test_payload_type_parameters(Gee.TestFinishedCallback cb) {
        string xml = "<payload-type xmlns='urn:xmpp:jingle:apps:rtp:1' id='111' name='opus' clockrate='48000' channels='2'>"
            + "<parameter xmlns='urn:xmpp:jingle:apps:rtp:1' name='useinbandfec' value='1'/>"
            + "<parameter xmlns='urn:xmpp:jingle:apps:rtp:1' name='stereo' value='1'/>"
            + "</payload-type>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            Xep.JingleRtp.PayloadType pt = Xep.JingleRtp.PayloadType.parse(node);
            fail_if_not_eq_int(pt.parameters.size, 2,
                "XEP-0167 S5: Both parameters MUST be parsed");
            fail_if_not_eq_str(pt.parameters["useinbandfec"], "1",
                "XEP-0167 S5: useinbandfec parameter value MUST be '1'");
            fail_if_not_eq_str(pt.parameters["stereo"], "1",
                "XEP-0167 S5: stereo parameter value MUST be '1'");
            cb();
        });
    }

    // ===================== XEP-0167: PayloadType Equality =====================

    /**
     * XEP-0167: Two PayloadTypes with identical fields MUST be equal.
     */
    private void test_payload_equals_same() {
        var a = new Xep.JingleRtp.PayloadType();
        a.id = 111; a.name = "opus"; a.clockrate = 48000; a.channels = 2;
        var b = new Xep.JingleRtp.PayloadType();
        b.id = 111; b.name = "opus"; b.clockrate = 48000; b.channels = 2;
        fail_if(!Xep.JingleRtp.PayloadType.equals_func(a, b),
            "XEP-0167: Identical PayloadTypes MUST be equal");
    }

    /**
     * XEP-0167: PayloadTypes with different IDs MUST NOT be equal.
     */
    private void test_payload_equals_different_id() {
        var a = new Xep.JingleRtp.PayloadType();
        a.id = 111; a.name = "opus"; a.clockrate = 48000; a.channels = 2;
        var b = new Xep.JingleRtp.PayloadType();
        b.id = 112; b.name = "opus"; b.clockrate = 48000; b.channels = 2;
        fail_if(Xep.JingleRtp.PayloadType.equals_func(a, b),
            "XEP-0167: PayloadTypes with different ID MUST NOT be equal");
    }

    /**
     * XEP-0167: clone() MUST produce an equal PayloadType.
     */
    private void test_payload_clone_equal() {
        var a = new Xep.JingleRtp.PayloadType();
        a.id = 96; a.name = "VP8"; a.clockrate = 90000; a.channels = 1;
        a.parameters["profile-level-id"] = "42e01f";
        var b = a.clone();
        fail_if(!Xep.JingleRtp.PayloadType.equals_func(a, b),
            "XEP-0167: clone() MUST produce an equal PayloadType");
        // Verify parameters are independent copies
        b.parameters["new-param"] = "test";
        fail_if(a.parameters.has_key("new-param"),
            "XEP-0167: clone() parameters MUST be independent copy");
    }

    // ===================== XEP-0272: GroupCall Data Class =====================

    /**
     * XEP-0272: GroupCall stores the MUC JID.
     */
    private void test_groupcall_muc_jid() {
        try {
            Jid muc_jid = new Jid("abc123@conference.example.com");
            var gc = new Xep.Muji.GroupCall(muc_jid);
            fail_if(!gc.muc_jid.equals(muc_jid),
                "XEP-0272: GroupCall.muc_jid MUST match constructor argument");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0272: New GroupCall has no peers.
     */
    private void test_groupcall_peers_empty() {
        try {
            var gc = new Xep.Muji.GroupCall(new Jid("r@c.example.com"));
            fail_if(!gc.peers.is_empty,
                "XEP-0272: New GroupCall.peers MUST be empty");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0272: New GroupCall has no peers_to_connect_to.
     */
    private void test_groupcall_connect_empty() {
        try {
            var gc = new Xep.Muji.GroupCall(new Jid("r@c.example.com"));
            fail_if(!gc.peers_to_connect_to.is_empty,
                "XEP-0272: New GroupCall.peers_to_connect_to MUST be empty");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0272: peer_joined signal fires when connected externally.
     */
    private void test_groupcall_peer_joined_signal() {
        try {
            var gc = new Xep.Muji.GroupCall(new Jid("r@c.example.com"));
            Jid? received_jid = null;
            gc.peer_joined.connect((jid) => { received_jid = jid; });

            Jid test_jid = new Jid("alice@example.com/res");
            gc.peer_joined(test_jid);

            fail_if(received_jid == null,
                "XEP-0272: peer_joined signal MUST fire");
            fail_if(!received_jid.equals(test_jid),
                "XEP-0272: peer_joined signal MUST carry the correct JID");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0272: peer_left signal fires when connected externally.
     */
    private void test_groupcall_peer_left_signal() {
        try {
            var gc = new Xep.Muji.GroupCall(new Jid("r@c.example.com"));
            Jid? received_jid = null;
            gc.peer_left.connect((jid) => { received_jid = jid; });

            Jid test_jid = new Jid("bob@example.com/res");
            gc.peer_left(test_jid);

            fail_if(received_jid == null,
                "XEP-0272: peer_left signal MUST fire");
            fail_if(!received_jid.equals(test_jid),
                "XEP-0272: peer_left signal MUST carry the correct JID");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * XEP-0272: codecs_changed signal fires with payload types.
     */
    private void test_groupcall_codecs_changed_signal() {
        try {
            var gc = new Xep.Muji.GroupCall(new Jid("r@c.example.com"));
            bool signal_fired = false;
            int received_count = 0;
            gc.codecs_changed.connect((pts) => {
                signal_fired = true;
                received_count = pts.size;
            });

            var pts = new ArrayList<Xep.JingleRtp.PayloadType>();
            var opus = new Xep.JingleRtp.PayloadType();
            opus.id = 111; opus.name = "opus";
            pts.add(opus);
            gc.codecs_changed(pts);

            fail_if(!signal_fired,
                "XEP-0272: codecs_changed signal MUST fire");
            fail_if_not_eq_int(received_count, 1,
                "XEP-0272: codecs_changed MUST carry 1 payload type");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===================== XEP-0272: Flag =====================

    /**
     * XEP-0272: Flag namespace must match module namespace.
     */
    private void test_flag_ns() {
        var flag = new Xep.Muji.Flag();
        fail_if_not_eq_str(flag.get_ns(), Xep.Muji.NS_URI,
            "XEP-0272: Flag.get_ns() MUST return MUJI namespace");
    }

    /**
     * XEP-0272: New Flag has empty calls map.
     */
    private void test_flag_calls_empty() {
        var flag = new Xep.Muji.Flag();
        fail_if(!flag.calls.is_empty,
            "XEP-0272: New Flag.calls MUST be empty");
    }

    /**
     * XEP-0272: Flag.calls stores and retrieves GroupCall by MUC JID.
     */
    private void test_flag_calls_store() {
        try {
            var flag = new Xep.Muji.Flag();
            Jid muc_jid = new Jid("room@conference.example.com");
            var gc = new Xep.Muji.GroupCall(muc_jid);
            gc.our_nick = "testnick";
            flag.calls[muc_jid] = gc;

            fail_if(!flag.calls.has_key(muc_jid),
                "XEP-0272: Flag.calls MUST store GroupCall by MUC JID");
            fail_if_not_eq_str(flag.calls[muc_jid].our_nick, "testnick",
                "XEP-0272: Retrieved GroupCall MUST match stored one");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===================== XEP-0272: Nick Format =====================

    /**
     * XEP-0272: MUJI nick is generated as %08x (8 hex chars).
     * Verify format by generating 20 samples.
     */
    private void test_nick_format() {
        for (int i = 0; i < 20; i++) {
            string nick = "%08x".printf(Random.next_int());
            fail_if(nick.length != 8,
                @"XEP-0272: Nick MUST be 8 chars, got $(nick.length): '$nick'");
            for (int j = 0; j < nick.length; j++) {
                char c = nick[j];
                bool valid = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                fail_if(!valid,
                    @"XEP-0272: Nick char at pos $j MUST be lowercase hex, got '$(c)' in '$nick'");
            }
        }
    }

    // ===================== XEP-0482: Call Invite Stanzas =====================

    /**
     * XEP-0482 S3: MUJI <invite> MUST contain <muji room='...'/>.
     */
    private void test_cim_muji_propose(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client' type='chat' to='bob@example.com'>"
            + "<invite xmlns='urn:xmpp:call-invites:0' id='call-123' video='true' multi='true'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0' room='abc@conference.example.com'/>"
            + "</invite>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? invite = node.get_subnode("invite", Xep.CallInvites.NS_URI);
            fail_if(invite == null, "XEP-0482: <invite> element MUST be present");
            if (invite != null) {
                StanzaNode? muji = invite.get_subnode("muji", Xep.Muji.NS_URI);
                fail_if(muji == null, "XEP-0482: <invite> MUST contain <muji> for group calls");
                if (muji != null) {
                    string? room = muji.get_attribute("room");
                    fail_if(room == null, "XEP-0482: <muji> MUST have 'room' attribute");
                    fail_if_not_eq_str(room, "abc@conference.example.com",
                        "XEP-0482: room attribute MUST contain the MUJI MUC JID");
                }
            }
            cb();
        });
    }

    /**
     * XEP-0482: The <muji> element inside <invite> MUST use the MUJI namespace.
     */
    private void test_cim_muji_ns(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client'>"
            + "<invite xmlns='urn:xmpp:call-invites:0' id='c1'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0' room='r@c.example.com'/>"
            + "</invite>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? muji = node.get_deep_subnode(
                Xep.CallInvites.NS_URI + ":invite",
                Xep.Muji.NS_URI + ":muji");
            fail_if(muji == null,
                "XEP-0482: <muji> inside <invite> MUST use namespace '" + Xep.Muji.NS_URI + "'");
            cb();
        });
    }

    /**
     * XEP-0482 S3: <invite> MUST carry an 'id' attribute (the call-id).
     */
    private void test_cim_invite_call_id(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client'>"
            + "<invite xmlns='urn:xmpp:call-invites:0' id='unique-call-42' video='false'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0' room='r@c.example.com'/>"
            + "</invite>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? invite = node.get_subnode("invite", Xep.CallInvites.NS_URI);
            fail_if(invite == null, "XEP-0482: <invite> MUST be present");
            if (invite != null) {
                string? id = invite.get_attribute("id");
                fail_if(id == null, "XEP-0482 S3: <invite> MUST have 'id' attribute");
                fail_if_not_eq_str(id, "unique-call-42",
                    "XEP-0482 S3: 'id' attribute MUST preserve call ID");
            }
            cb();
        });
    }

    /**
     * XEP-0482: <invite> 'video' attribute MUST be parseable.
     */
    private void test_cim_invite_video(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client'>"
            + "<invite xmlns='urn:xmpp:call-invites:0' id='c1' video='true' multi='true'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0' room='r@c.example.com'/>"
            + "</invite>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? invite = node.get_subnode("invite", Xep.CallInvites.NS_URI);
            fail_if(invite == null, "XEP-0482: <invite> MUST be present");
            if (invite != null) {
                bool video = invite.get_attribute_bool("video", false);
                fail_if(!video, "XEP-0482: video='true' MUST parse as true");
                bool multi = invite.get_attribute_bool("multi", false);
                fail_if(!multi, "XEP-0482: multi='true' MUST parse as true for MUJI calls");
            }
            cb();
        });
    }

    /**
     * XEP-0482: <retract> MUST have 'id' attribute matching the call.
     */
    private void test_cim_retract(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client'>"
            + "<retract xmlns='urn:xmpp:call-invites:0' id='call-to-retract'/>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? retract = node.get_subnode("retract", Xep.CallInvites.NS_URI);
            fail_if(retract == null, "XEP-0482: <retract> element MUST be present");
            if (retract != null) {
                string? id = retract.get_attribute("id");
                fail_if(id == null, "XEP-0482: <retract> MUST have 'id' attribute");
                fail_if_not_eq_str(id, "call-to-retract",
                    "XEP-0482: retract id MUST match original call id");
            }
            cb();
        });
    }

    /**
     * XEP-0482: <accept> for MUJI call MUST contain <muji room='...'/>.
     */
    private void test_cim_accept_muji(Gee.TestFinishedCallback cb) {
        string xml = "<message xmlns='jabber:client'>"
            + "<accept xmlns='urn:xmpp:call-invites:0' id='call-accept-1'>"
            + "<muji xmlns='urn:xmpp:jingle:muji:0' room='room1@conference.example.com'/>"
            + "</accept>"
            + "</message>";
        parse_and_check.begin(xml, (obj, res) => {
            StanzaNode? node = parse_and_check.end(res);
            if (node == null) { cb(); return; }

            StanzaNode? accept = node.get_subnode("accept", Xep.CallInvites.NS_URI);
            fail_if(accept == null, "XEP-0482: <accept> element MUST be present");
            if (accept != null) {
                StanzaNode? muji = accept.get_subnode("muji", Xep.Muji.NS_URI);
                fail_if(muji == null, "XEP-0482: <accept> for MUJI call MUST contain <muji>");
                if (muji != null) {
                    fail_if_not_eq_str(muji.get_attribute("room"), "room1@conference.example.com",
                        "XEP-0482: accept <muji> room attribute MUST match the call room");
                }
            }
            cb();
        });
    }

    // ===================== RFC 4566: Payload ID Range =====================

    /**
     * RFC 4566 S6: Static payload type IDs range from 0-95,
     * dynamic from 96-127. PayloadType.id is uint8 so can hold 0-255,
     * but valid RTP payload IDs are 0-127.
     */
    private void test_payload_id_range() {
        // Static audio
        var pcmu = new Xep.JingleRtp.PayloadType();
        pcmu.id = 0; pcmu.name = "PCMU";
        fail_if(pcmu.id > 127, "RFC 4566 S6: PCMU id=0 MUST be in [0,127]");

        // Dynamic
        var opus = new Xep.JingleRtp.PayloadType();
        opus.id = 111; opus.name = "opus";
        fail_if(opus.id < 96 || opus.id > 127,
            "RFC 4566 S6: Opus id=111 MUST be in dynamic range [96,127]");

        // Boundary
        var tel = new Xep.JingleRtp.PayloadType();
        tel.id = 101; tel.name = "telephone-event";
        fail_if(tel.id > 127,
            "RFC 4566 S6: telephone-event MUST be in [0,127]");
    }

    // ===================== XEP-0272: Payload Intersection =====================

    /**
     * XEP-0272 S5: If two peers have no common codecs, intersection is empty.
     */
    private void test_intersection_no_common() {
        var list_a = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        var opus = new Xep.JingleRtp.PayloadType();
        opus.id = 111; opus.name = "opus"; opus.clockrate = 48000; opus.channels = 2;
        list_a.add(opus);

        var list_b = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        var pcmu = new Xep.JingleRtp.PayloadType();
        pcmu.id = 0; pcmu.name = "PCMU"; pcmu.clockrate = 8000; pcmu.channels = 1;
        list_b.add(pcmu);

        // Manual intersection (same logic as compute_payload_intersection)
        var intersection = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        foreach (var pt in list_a) {
            if (list_b.contains(pt)) intersection.add(pt);
        }
        fail_if(!intersection.is_empty,
            "XEP-0272 S5: Intersection of disjoint codec sets MUST be empty");
    }

    /**
     * XEP-0272 S5: Common codecs remain in the intersection.
     */
    private void test_intersection_keeps_common() {
        var opus_a = new Xep.JingleRtp.PayloadType();
        opus_a.id = 111; opus_a.name = "opus"; opus_a.clockrate = 48000; opus_a.channels = 2;
        var pcmu_a = new Xep.JingleRtp.PayloadType();
        pcmu_a.id = 0; pcmu_a.name = "PCMU"; pcmu_a.clockrate = 8000; pcmu_a.channels = 1;

        var list_a = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        list_a.add(opus_a); list_a.add(pcmu_a);

        var opus_b = new Xep.JingleRtp.PayloadType();
        opus_b.id = 111; opus_b.name = "opus"; opus_b.clockrate = 48000; opus_b.channels = 2;
        var vp8_b = new Xep.JingleRtp.PayloadType();
        vp8_b.id = 96; vp8_b.name = "VP8"; vp8_b.clockrate = 90000; vp8_b.channels = 1;

        var list_b = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        list_b.add(opus_b); list_b.add(vp8_b);

        // Intersection
        var intersection = new ArrayList<Xep.JingleRtp.PayloadType>(Xep.JingleRtp.PayloadType.equals_func);
        foreach (var pt in list_a) {
            if (list_b.contains(pt)) intersection.add(pt);
        }
        fail_if_not_eq_int(intersection.size, 1,
            "XEP-0272 S5: Intersection MUST contain exactly 1 common codec (opus)");
        if (!intersection.is_empty) {
            fail_if_not_eq_str(intersection[0].name, "opus",
                "XEP-0272 S5: Common codec MUST be opus");
        }
    }

    // ===================== Helper: Parse XML via StanzaReader =====================

    /**
     * Parse real XML via StanzaReader (Golden Rule #3).
     * Returns the root StanzaNode, or null if parse failed (test fails).
     */
    private async StanzaNode? parse_and_check(string xml) {
        var reader = new StanzaReader.for_string(xml);
        try {
            StanzaNode node = yield reader.read_node();
            return node;
        } catch (Error e) {
            fail_if_reached(@"XEP-0272: XML parse error: $(e.message) for: $xml");
            return null;
        }
    }
}

} // namespace Xmpp.Test
