using Gee;
using Xmpp;
using Xmpp.Xep;
using Omemo;

namespace Dino.Plugins.Omemo {

private const string NS_URI_V2 = Xmpp.Xep.Omemo.NS_URI_V2;
private const string NODE_DEVICELIST_V2 = Xmpp.Xep.Omemo.NODE_DEVICELIST_V2;
private const string NODE_BUNDLES_V2 = Xmpp.Xep.Omemo.NODE_BUNDLES_V2;

private const int NUM_KEYS_TO_PUBLISH_V2 = 100;

/**
 * OMEMO 2 stream module -- manages PEP interaction for device lists and bundles.
 *
 * Key differences from legacy StreamModule:
 * - Device list: urn:xmpp:omemo:2:devices (<devices><device id='...' label='...'/></devices>)
 * - Bundles: urn:xmpp:omemo:2:bundles (multi-item node, item_id = device_id)
 * - Bare 32-byte X25519 keys (no 0x05 prefix)
 * - Bundle XML: <spk>, <spks>, <ik>, <pk> elements
 */
public class StreamModule2 : XmppStreamModule {
    public static Xmpp.ModuleIdentity<StreamModule2> IDENTITY = new Xmpp.ModuleIdentity<StreamModule2>(NS_URI_V2, "omemo2_module");
    private static TimeSpan IGNORE_TIME = TimeSpan.MINUTE;

    public Store store { public get; private set; }
    public string? own_device_label { get; set; default = null; }
    private ConcurrentSet<string> active_bundle_requests = new ConcurrentSet<string>();
    private HashMap<Jid, Future<ArrayList<int32>>> active_devicelist_requests = new HashMap<Jid, Future<ArrayList<int32>>>(Jid.hash_func, Jid.equals_func);
    private Map<string, DateTime> device_ignore_time = new HashMap<string, DateTime>();

    public signal void device_list_loaded(Jid jid, ArrayList<int32> devices);
    public signal void device_label_received(Jid jid, int32 device_id, string label);
    public signal void bundle_fetched(Jid jid, int device_id, Bundle2 bundle);
    public signal void bundle_fetch_failed(Jid jid, int device_id);

    public StreamModule2(Store store) {
        this.store = store;
    }

    public override string get_id() { return IDENTITY.id; }
    public override string get_ns() { return IDENTITY.ns; }

    public override void attach(XmppStream stream) {
        stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).add_filtered_notification(stream, NODE_DEVICELIST_V2,
                (stream, jid, id, node) => parse_device_list(stream, jid, id, node), null, null);
    }

    public override void detach(XmppStream stream) {
        stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).remove_filtered_notification(stream, NODE_DEVICELIST_V2);
    }

    public async ArrayList<int32> request_user_devicelist(XmppStream stream, Jid jid) {
        var future = active_devicelist_requests[jid];
        if (future == null) {
            var promise = new Promise<ArrayList<int32>?>();
            future = promise.future;
            active_devicelist_requests[jid] = future;

            stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).request(stream, jid, NODE_DEVICELIST_V2, (stream, jid, id, node) => {
                ArrayList<int32> device_list = parse_device_list(stream, jid, id, node);
                promise.set_value(device_list);
                active_devicelist_requests.unset(jid);
            });
        }

        try {
            ArrayList<int32> device_list = yield future.wait_async();
            return device_list;
        } catch (FutureError error) {
            warning("OMEMO 2: Future error when waiting for device list: %s", error.message);
            return new ArrayList<int32>();
        }
    }

    /**
     * Parse OMEMO 2 device list:
     * <devices xmlns='urn:xmpp:omemo:2'>
     *   <device id='12345' label='Phone'/>
     * </devices>
     */
    public ArrayList<int32> parse_device_list(XmppStream stream, Jid jid, string? id, StanzaNode? node_) {
        ArrayList<int32> device_list = new ArrayList<int32>();

        StanzaNode node = node_ ?? new StanzaNode.build("devices", NS_URI_V2).add_self_xmlns();
        Jid? my_jid = stream.get_flag(Bind.Flag.IDENTITY).my_jid;
        if (my_jid == null) return device_list;

        if (jid.equals_bare(my_jid) && store.local_registration_id != 0) {
            bool am_on_devicelist = false;
            foreach (StanzaNode device_node in node.get_subnodes("device")) {
                int device_id = device_node.get_attribute_int("id");
                if (store.local_registration_id == device_id) {
                    am_on_devicelist = true;
                }
            }
            if (!am_on_devicelist) {
                debug("OMEMO 2: Not on device list, adding id %u", store.local_registration_id);
                var own_node = new StanzaNode.build("device", NS_URI_V2)
                    .put_attribute("id", store.local_registration_id.to_string());
                if (own_device_label != null && own_device_label.length > 0) {
                    own_node.put_attribute("label", own_device_label);
                }
                node.put_node(own_node);
                stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).publish.begin(stream, jid, NODE_DEVICELIST_V2, id, node, null, true, () => {
                    try_make_node_public.begin(stream, NODE_DEVICELIST_V2);
                });
            }
            publish_bundles_if_needed(stream, jid);
        }

        foreach (StanzaNode device_node in node.get_subnodes("device")) {
            int32 did = device_node.get_attribute_int("id");
            device_list.add(did);
            string? label = device_node.get_attribute("label");
            if (label != null && label.length > 0) {
                device_label_received(jid, did, label);
            }
        }
        device_list_loaded(jid, device_list);

        return device_list;
    }

    public void fetch_bundles(XmppStream stream, Jid jid, Gee.List<int32> devices) {
        Address address = new Address(jid.bare_jid.to_string(), 0);
        foreach (int32 device_id in devices) {
            if (!is_ignored_device(jid, device_id)) {
                address.device_id = device_id;
                try {
                    if (!store.contains_session(address)) {
                        fetch_bundle(stream, jid, device_id);
                    }
                } catch (Error e) {
                    // Ignore
                }
            }
        }
        address.device_id = 0;
    }

    /**
     * Fetch bundle from multi-item PEP node.
     * OMEMO 2: single node urn:xmpp:omemo:2:bundles, item_id = device_id.
     */
    public void fetch_bundle(XmppStream stream, Jid jid, int device_id, bool ignore_if_non_present = true) {
        if (active_bundle_requests.add(jid.bare_jid.to_string() + @":v2:$device_id")) {
            debug("OMEMO 2: Asking for bundle for %s/%d", jid.bare_jid.to_string(), device_id);
            /* Use request_item for multi-item PEP node */
            fetch_bundle_async.begin(stream, jid, device_id, ignore_if_non_present);
        }
    }

    private async void fetch_bundle_async(XmppStream stream, Jid jid, int device_id, bool ignore_if_non_present) {
        StanzaNode? bundle_node = yield stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY)
            .request_item(stream, jid.bare_jid, NODE_BUNDLES_V2, device_id.to_string());

        on_other_bundle_result(stream, jid, device_id, bundle_node, ignore_if_non_present);
    }

    public void ignore_device(Jid jid, int32 device_id) {
        if (device_id <= 0) return;
        lock (device_ignore_time) {
            device_ignore_time[jid.bare_jid.to_string() + @":v2:$device_id"] = new DateTime.now_utc();
        }
    }

    public void unignore_device(Jid jid, int32 device_id) {
        if (device_id <= 0) return;
        lock (device_ignore_time) {
            device_ignore_time.unset(jid.bare_jid.to_string() + @":v2:$device_id");
        }
    }

    public bool is_ignored_device(Jid jid, int32 device_id) {
        if (device_id <= 0) return true;
        lock (device_ignore_time) {
            string id = jid.bare_jid.to_string() + @":v2:$device_id";
            if (device_ignore_time.has_key(id)) {
                return new DateTime.now_utc().difference(device_ignore_time[id]) < IGNORE_TIME;
            }
        }
        return false;
    }

    public void clear_device_list(XmppStream stream) {
        stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).delete_node(stream, null, NODE_DEVICELIST_V2);
    }

    private void on_other_bundle_result(XmppStream stream, Jid jid, int device_id, StanzaNode? node, bool ignore_if_non_present) {
        if (node == null) {
            if (ignore_if_non_present) {
                debug("OMEMO 2: Ignoring device %s/%d: No bundle", jid.bare_jid.to_string(), device_id);
                ignore_device(jid, device_id);
            }
            bundle_fetch_failed(jid, device_id);
        } else {
            Bundle2 bundle = new Bundle2(node);
            unignore_device(jid, device_id);
            debug("OMEMO 2: Received bundle for %s/%d (identity_key_present=%s)",
                jid.bare_jid.to_string(),
                device_id,
                (bundle.identity_key != null).to_string());
            bundle_fetched(jid, device_id, bundle);
        }
        active_bundle_requests.remove(jid.bare_jid.to_string() + @":v2:$device_id");
    }

    public bool start_session(XmppStream stream, Jid jid, int32 device_id, Bundle2 bundle) {
        bool fail = false;
        int32 signed_pre_key_id = bundle.signed_pre_key_id;
        ECPublicKey? signed_pre_key = bundle.signed_pre_key;
        uint8[]? signed_pre_key_signature = bundle.signed_pre_key_signature;
        ECPublicKey? identity_key = bundle.identity_key;

        ArrayList<Bundle2.PreKey2> pre_keys = bundle.pre_keys;
        if (signed_pre_key_id < 0 || signed_pre_key == null || signed_pre_key_signature == null || identity_key == null || pre_keys.size == 0) {
            fail = true;
        } else {
            int pre_key_idx = Random.int_range(0, pre_keys.size);
            int32 pre_key_id = pre_keys[pre_key_idx].key_id;
            ECPublicKey? pre_key = pre_keys[pre_key_idx].key;
            if (pre_key_id < 0 || pre_key == null) {
                fail = true;
            } else {
                Address address = new Address(jid.bare_jid.to_string(), device_id);
                try {
                    if (store.contains_session(address)) {
                        return false;
                    }
                    debug("OMEMO 2: Starting new session with %s/%d", jid.bare_jid.to_string(), device_id);
                    SessionBuilder builder = store.create_session_builder(address);
                    builder.version = 4; // OMEMO 2: verify signature on bare 32-byte key
                    builder.process_pre_key_bundle(create_pre_key_bundle(device_id, device_id, pre_key_id, pre_key, signed_pre_key_id, signed_pre_key, signed_pre_key_signature, identity_key));
                } catch (Error e) {
                    debug("OMEMO 2: Can't create session with %s/%d: %s", jid.bare_jid.to_string(), device_id, e.message);
                    fail = true;
                }
                address.device_id = 0;
            }
        }
        if (fail) {
            debug("OMEMO 2: Ignoring device %s/%d: Bad bundle", jid.bare_jid.to_string(), device_id);
            ignore_device(jid, device_id);
        }
        return true;
    }

    public void publish_bundles_if_needed(XmppStream stream, Jid jid) {
        string key = jid.bare_jid.to_string() + @":v2:$(store.local_registration_id)";
        debug("OMEMO 2: publish_bundles_if_needed called for %s, key=%s", jid.bare_jid.to_string(), key);
        if (active_bundle_requests.add(key)) {
            debug("OMEMO 2: Starting fetch_self_bundle for %s", jid.bare_jid.to_string());
            /* For OMEMO 2, fetch our own bundle from multi-item node */
            fetch_self_bundle.begin(stream, jid);
        } else {
            debug("OMEMO 2: Bundle request already active for %s", jid.bare_jid.to_string());
        }
    }

    private async void fetch_self_bundle(XmppStream stream, Jid jid) {
        debug("OMEMO 2: fetch_self_bundle requesting item from %s node=%s id=%s", jid.bare_jid.to_string(), NODE_BUNDLES_V2, store.local_registration_id.to_string());
        StanzaNode? node = yield stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY)
            .request_item(stream, jid, NODE_BUNDLES_V2, store.local_registration_id.to_string());
        debug("OMEMO 2: fetch_self_bundle result: node=%s", node != null ? "present" : "NULL");
        yield on_self_bundle_result(stream, jid, node);
    }

    private async void on_self_bundle_result(XmppStream stream, Jid jid, StanzaNode? node) {
        debug("OMEMO 2: on_self_bundle_result called, node=%s", node != null ? "present" : "NULL");
        if (!Plugin.ensure_context()) {
            debug("OMEMO 2: on_self_bundle_result: ensure_context FAILED, aborting");
            return;
        }
        Map<int, ECPublicKey> keys = new HashMap<int, ECPublicKey>();
        ECPublicKey? identity_key = null;
        int32 signed_pre_key_id = -1;
        ECPublicKey? signed_pre_key = null;
        SignedPreKeyRecord? signed_pre_key_record = null;
        bool changed = false;

        if (node == null) {
            debug("OMEMO 2: No existing bundle found, will publish new one");
            identity_key = store.identity_key_pair.public;
            changed = true;
        } else {
            Bundle2 bundle = new Bundle2(node);
            foreach (Bundle2.PreKey2 prekey in bundle.pre_keys) {
                ECPublicKey? key = prekey.key;
                if (key != null) {
                    keys[prekey.key_id] = (!)key;
                }
            }
            identity_key = bundle.identity_key;
            signed_pre_key_id = bundle.signed_pre_key_id;
            signed_pre_key = bundle.signed_pre_key;
        }

        try {
            /* Validate IdentityKey */
            if (identity_key == null || store.identity_key_pair.public.compare((!)identity_key) != 0) {
                changed = true;
            }
            IdentityKeyPair identity_key_pair = store.identity_key_pair;

            /* Validate signedPreKeyRecord + ID */
            if (signed_pre_key == null || signed_pre_key_id == -1 || !store.contains_signed_pre_key(signed_pre_key_id) || store.load_signed_pre_key(signed_pre_key_id).key_pair.public.compare((!)signed_pre_key) != 0) {
                signed_pre_key_id = (int32)store.signed_pre_key_store.get_max_key_id() + 1;
                if (signed_pre_key_id <= 0) signed_pre_key_id = 1;

                signed_pre_key_record = Plugin.get_context().generate_signed_pre_key(identity_key_pair, signed_pre_key_id);
                store.store_signed_pre_key((!)signed_pre_key_record);
                changed = true;
            } else {
                signed_pre_key_record = store.load_signed_pre_key(signed_pre_key_id);
            }

            /* Upgrade SPK if signature_omemo is missing (pre-OMEMO2 keys) */
            if (signed_pre_key_record != null && signed_pre_key_record.signature_omemo.length == 0) {
                debug("OMEMO 2: SPK %u missing signature_omemo, upgrading...", signed_pre_key_record.id);
                SignedPreKeyRecord upgraded = signed_pre_key_record;
                Protocol.KeyHelper.upgrade_signed_pre_key(ref upgraded, identity_key_pair, Plugin.get_context().native_context);
                signed_pre_key_record = upgraded;
                store.store_signed_pre_key((!)signed_pre_key_record);
                changed = true;
            }

            /* Validate PreKeys */
            Set<PreKeyRecord> pre_key_records = new HashSet<PreKeyRecord>();
            foreach (var entry in keys.entries) {
                if (store.contains_pre_key(entry.key)) {
                    PreKeyRecord record = store.load_pre_key(entry.key);
                    if (record.key_pair.public.compare(entry.value) == 0) {
                        pre_key_records.add(record);
                    }
                }
            }
            int new_keys = NUM_KEYS_TO_PUBLISH_V2 - pre_key_records.size;
            if (new_keys > 0) {
                int32 next_id = (int32)store.pre_key_store.get_max_key_id() + 1;
                if (next_id <= 0) next_id = 1;

                Set<PreKeyRecord> new_records = Plugin.get_context().generate_pre_keys((uint)next_id, (uint)new_keys);
                pre_key_records.add_all(new_records);
                foreach (PreKeyRecord record in new_records) {
                    store.store_pre_key(record);
                }
                changed = true;
            }

            debug("OMEMO 2: Bundle check complete: changed=%s, pre_keys=%d", changed.to_string(), pre_key_records.size);
            if (changed) {
                debug("OMEMO 2: Publishing v2 bundle for device %d", (int32)store.local_registration_id);
                yield publish_bundle_v2(stream, (!)signed_pre_key_record, identity_key_pair, pre_key_records, (int32)store.local_registration_id);
                debug("OMEMO 2: Bundle published successfully");
            } else {
                debug("OMEMO 2: Bundle unchanged, not publishing");
            }
        } catch (Error e) {
            warning("OMEMO 2: Unexpected error while publishing bundle: %s", e.message);
        }
        active_bundle_requests.remove(jid.bare_jid.to_string() + @":v2:$(store.local_registration_id)");
    }

    /**
     * Publish OMEMO 2 bundle to multi-item PEP node.
     * Key formats per OMEMO 2 (XEP-0384) and QXmpp interop:
     *   IK  = Ed25519 (ec_public_key_get_ed)
     *   SPK = X25519/Montgomery (ec_public_key_get_mont)
     *   PKs = X25519/Montgomery (ec_public_key_get_mont)
     */
    public async void publish_bundle_v2(XmppStream stream, SignedPreKeyRecord signed_pre_key_record, IdentityKeyPair identity_key_pair, Set<PreKeyRecord> pre_key_records, int32 device_id) throws Error {
        ECKeyPair tmp;
        /* IK must be Ed25519, SPK must be Montgomery/X25519 */
        uint8[] ik_bytes = identity_key_pair.public.ed.data;
        uint8[] spk_bytes = (tmp = signed_pre_key_record.key_pair).public.mont.data;
        uint8[] sig_omemo = signed_pre_key_record.signature_omemo;
        uint8[] sig_legacy = signed_pre_key_record.signature;
        debug("OMEMO 2: Bundle IK %d bytes (Ed25519), SPK %d bytes (Mont)", ik_bytes.length, spk_bytes.length);
        debug("OMEMO 2: SPK signature_omemo %d bytes, signature_legacy %d bytes", sig_omemo.length, sig_legacy.length);
        debug("OMEMO 2: SPK id=%u", signed_pre_key_record.id);

        /* Verify the OMEMO signature locally, simulating what QXmpp/Kaidan does */
        ECPublicKey verify_ik;
        curve_decode_point_ed(out verify_ik, ik_bytes, Plugin.get_context().native_context);
        ECPublicKey verify_spk;
        curve_decode_point_mont(out verify_spk, spk_bytes, Plugin.get_context().native_context);
        uint8[] verify_spk_serialized = verify_spk.serialize_omemo();
        debug("OMEMO 2: Verify: IK decoded (has_ed=%s), SPK decoded, SPK serialized %d bytes",
              verify_ik.ed != null ? "true" : "false", verify_spk_serialized.length);
        int verify_result = Curve.verify_signature(verify_ik, verify_spk_serialized, sig_omemo);
        debug("OMEMO 2: Local SPK signature verification result: %d (1=valid, 0=invalid, <0=error)", verify_result);

        StanzaNode bundle = new StanzaNode.build("bundle", NS_URI_V2)
                .add_self_xmlns()
                .put_node(new StanzaNode.build("spk", NS_URI_V2)
                    .put_attribute("id", signed_pre_key_record.id.to_string())
                    .put_node(new StanzaNode.text(Base64.encode(spk_bytes))))
                .put_node(new StanzaNode.build("spks", NS_URI_V2)
                    .put_node(new StanzaNode.text(Base64.encode(signed_pre_key_record.signature_omemo))))
                .put_node(new StanzaNode.build("ik", NS_URI_V2)
                    .put_node(new StanzaNode.text(Base64.encode(ik_bytes))));

        StanzaNode prekeys = new StanzaNode.build("prekeys", NS_URI_V2);
        foreach (PreKeyRecord pre_key_record in pre_key_records) {
            uint8[] pk_bytes = pre_key_record.key_pair.public.mont.data;
            prekeys.put_node(new StanzaNode.build("pk", NS_URI_V2)
                    .put_attribute("id", pre_key_record.id.to_string())
                    .put_node(new StanzaNode.text(Base64.encode(pk_bytes))));
        }
        bundle.put_node(prekeys);

        /* Publish to multi-item node with item_id = device_id */
        debug("OMEMO 2: About to publish bundle to node %s with item_id %s", NODE_BUNDLES_V2, device_id.to_string());
        bool result = yield stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).publish(stream, null, NODE_BUNDLES_V2, device_id.to_string(), bundle);
        debug("OMEMO 2: Bundle publish result: %s", result ? "SUCCESS" : "FAILURE");
        yield try_make_node_public(stream, NODE_BUNDLES_V2);
    }

    private async void try_make_node_public(XmppStream stream, string node_id) {
        debug("OMEMO 2: try_make_node_public for %s", node_id);
        DataForms.DataForm? data_form = yield stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).request_node_config(stream, null, node_id);
        if (data_form == null) {
            debug("OMEMO 2: try_make_node_public: data_form is NULL for %s", node_id);
            return;
        }

        bool needs_submit = false;
        foreach (DataForms.DataForm.Field field in data_form.fields) {
            if (field.var == "pubsub#access_model" && field.get_value_string() != Pubsub.ACCESS_MODEL_OPEN) {
                debug("OMEMO 2: Changing access_model from %s to %s", field.get_value_string(), Pubsub.ACCESS_MODEL_OPEN);
                field.set_value_string(Pubsub.ACCESS_MODEL_OPEN);
                needs_submit = true;
            }
            if (field.var == "pubsub#max_items" && field.get_value_string() != "max") {
                debug("OMEMO 2: Changing max_items from %s to max", field.get_value_string());
                field.set_value_string("max");
                needs_submit = true;
            }
        }
        if (needs_submit) {
            yield stream.get_module<Pubsub.Module>(Pubsub.Module.IDENTITY).submit_node_config(stream, null, data_form, node_id);
            debug("OMEMO 2: Node config updated for %s", node_id);
        }
        debug("OMEMO 2: try_make_node_public done for %s", node_id);
    }
}

}
