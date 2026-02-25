using Dino.Entities;
using Gee;
using Xmpp;

public class Dino.CallState : Object {

    public const int MAX_MUJI_PEERS = 4;
    public const string CALL_FULL_REASON = "call-full";

    public signal void terminated(Jid who_terminated, string? reason_name, string? reason_text);
    public signal void peer_joined(Jid jid, PeerState peer_state);
    public signal void peer_left(Jid jid, PeerState peer_state, string? reason_name, string? reason_text);

    public StreamInteractor stream_interactor;
    public Plugins.VideoCallPlugin call_plugin = Dino.Application.get_default().plugin_registry.video_call_plugin;
    public Call call;
    public Jid? invited_to_group_call = null;
    public bool accepted { get; private set; default=false; }

    public bool use_cim = false;
    public string? cim_call_id = null;
    public Jid? cim_counterpart = null;
    public ArrayList<Jid> cim_jids_to_inform = new ArrayList<Jid>();
    public string cim_message_type { get; set; default=Xmpp.MessageStanza.TYPE_CHAT; }

    public Xep.Muji.GroupCall? group_call { get; set; }
    public bool we_should_send_audio { get; set; default=false; }
    public bool we_should_send_video { get; set; default=false; }

    public HashMap<Jid, PeerState> peers = new HashMap<Jid, PeerState>(Jid.hash_func, Jid.equals_func);

    private HashMap<Jid, uint> invite_timeout_ids = new HashMap<Jid, uint>(Jid.hash_bare_func, Jid.equals_bare_func);
    private uint establishing_timeout_id = 0;
    private uint muji_empty_muc_timeout_id = 0;
    private bool group_call_converting = false;

    private Plugins.MediaDevice selected_microphone_device;
    private Plugins.MediaDevice selected_speaker_device;
    private Plugins.MediaDevice selected_video_device;

    public CallState(Call call, StreamInteractor stream_interactor) {
        this.call = call;
        this.stream_interactor = stream_interactor;

        if (call.direction == Call.DIRECTION_OUTGOING && call.state != Call.State.OTHER_DEVICE) {
            accepted = true;
            // Timeout is started separately per call type (1:1 or MUJI)
        }
    }

    internal async void initiate_groupchat_call(Jid muc) {
        cim_jids_to_inform.add(muc);
        cim_message_type = MessageStanza.TYPE_GROUPCHAT;

        if (this.group_call == null) yield convert_into_group_call();
        if (this.group_call == null) return;
        // The user might have retracted the call in the meanwhile
        if (this.call.state != Call.State.RINGING) return;

        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream == null) return;

        Gee.List<Jid> occupants = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_other_occupants(muc, call.account);
        foreach (Jid occupant in occupants) {
            Jid? real_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_real_jid(occupant, call.account);
            if (real_jid == null) continue;
            debug(@"Adding MUC member as MUJI MUC owner %s", real_jid.bare_jid.to_string());
            yield stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).change_affiliation(stream, group_call.muc_jid, real_jid.bare_jid, null, "owner");
        }

        stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_muji_propose(stream, cim_call_id, muc, group_call.muc_jid, we_should_send_video, cim_message_type);
    }

    internal PeerState set_first_peer(Jid peer) {
        var peer_state = new PeerState(peer, call, this, stream_interactor);
        peer_state.first_peer = true;
        add_peer(peer_state);
        return peer_state;
    }

    internal void add_peer(PeerState peer) {
        call.add_peer(peer.jid.bare_jid);
        connect_peer_signals(peer);
        peer_joined(peer.jid, peer);
    }

    internal void on_peer_stream_created(PeerState peer, string media) {
        if (media == "audio") {
            call_plugin.set_device(peer.get_audio_stream(), get_microphone_device());
            call_plugin.set_device(peer.get_audio_stream(), get_speaker_device());
        } else if (media == "video") {
            call_plugin.set_device(peer.get_video_stream(), get_video_device());
        }
    }

    public void accept() {
        accepted = true;
        call.state = Call.State.ESTABLISHING;
        cancel_all_timeouts();

        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream == null) return;

        if (use_cim) {
            if (invited_to_group_call != null) {
                join_group_call.begin(invited_to_group_call);

                foreach (Jid jid_to_inform in cim_jids_to_inform) {
                    stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_muji_accept(stream, jid_to_inform, cim_call_id, invited_to_group_call, cim_message_type);
                }
            } else if (peers.size == 1) {
                string sid = peers.values.to_array()[0].sid;
                foreach (Jid jid_to_inform in cim_jids_to_inform) {
                    stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_jingle_accept(stream, jid_to_inform, cim_call_id, sid, cim_message_type);
                }
            }
        } else {
            foreach (PeerState peer in peers.values) {
                peer.accept();
            }
        }
    }

    public void reject() {
        call.state = Call.State.DECLINED;

        if (use_cim) {
            XmppStream stream = stream_interactor.get_stream(call.account);
            if (stream == null) return;

            foreach (Jid jid_to_inform in cim_jids_to_inform) {
                stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_reject(stream, jid_to_inform, cim_call_id, cim_message_type);
            }
        }
        var peers_cpy = new ArrayList<PeerState>();
        peers_cpy.add_all(peers.values);
        foreach (PeerState peer in peers_cpy) {
            peer.reject();
        }
        terminated(call.account.bare_jid, null, null);
    }

    public void end(string? reason_text = null) {
        // Cancel all pending timeouts
        cancel_all_timeouts();

        var peers_cpy = new ArrayList<PeerState>();
        peers_cpy.add_all(peers.values);

        // Capture group_call ref before nulling — prevents double-leave
        // from handle_peer_left() which is triggered by peer.end() below.
        Xep.Muji.GroupCall? gc = this.group_call;
        this.group_call = null;

        // Terminate sessions, send out messages about the ended call, exit MUC if applicable
        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream != null) {
            // Terminate all peer Jingle sessions FIRST (closes streams,
            // releases camera/mic) BEFORE exiting the MUC — otherwise
            // the MUC exit triggers peer_left events that race with the
            // explicit termination loop below.
            if (call.state == Call.State.IN_PROGRESS || call.state == Call.State.ESTABLISHING) {
                foreach (PeerState peer in peers_cpy) {
                    peer.end(Xep.Jingle.ReasonElement.SUCCESS, reason_text);
                }
                if (use_cim) {
                    foreach (Jid jid_to_inform in cim_jids_to_inform) {
                        stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_left(stream, jid_to_inform, cim_call_id, cim_message_type);
                    }
                }
            } else if (call.state == Call.State.RINGING) {
                foreach (PeerState peer in peers_cpy) {
                    peer.end(Xep.Jingle.ReasonElement.CANCEL, reason_text);
                }
                if (call.direction == Call.DIRECTION_OUTGOING && use_cim) {
                    foreach (Jid jid_to_inform in cim_jids_to_inform) {
                        stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_retract(stream, jid_to_inform, cim_call_id, cim_message_type);
                    }
                }
            }
        }

        // NOW exit/destroy the MUJI MUC — after all Jingle sessions are
        // terminated and all streams/devices are released.
        if (gc != null && stream != null) {
            // Clean up the MUJI flag
            var flag = stream.get_flag(Xep.Muji.Flag.IDENTITY);
            if (flag != null) flag.calls.unset(gc.muc_jid);

            // Destroy the ephemeral MUC (we are owner). If that fails,
            // fall back to just leaving.
            stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).destroy_room.begin(
                stream, gc.muc_jid, "Call ended", null, (_, res) => {
                try {
                    stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).destroy_room.end(res);
                    debug("MUJI MUC %s destroyed", gc.muc_jid.to_string());
                } catch (Error e) {
                    debug("Could not destroy MUJI MUC %s: %s — leaving instead", gc.muc_jid.to_string(), e.message);
                    stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).exit(stream, gc.muc_jid);
                }
            });

            // Remove the ephemeral MUJI conversation from the sidebar
            Conversation? muji_conv = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY)
                .get_conversation(gc.muc_jid, call.account, Conversation.Type.GROUPCHAT);
            if (muji_conv != null) {
                stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).close_conversation(muji_conv);
            }
        }

        // Update the call state
        if (call.state == Call.State.IN_PROGRESS || call.state == Call.State.ESTABLISHING) {
            call.state = Call.State.ENDED;
        } else if (call.state == Call.State.RINGING) {
            call.state = Call.State.MISSED;
        } else {
            return;
        }

        call.end_time = new DateTime.now_utc();

        // Safety net: force-destroy the GStreamer pipeline in case any
        // zombie streams survived (e.g. from async call_resource() that
        // completed after end() ran).  Scheduled as idle so that any
        // pending close_stream() calls from session.terminate() above
        // finish first.
        Idle.add(() => {
            call_plugin.dispose_pipeline();
            return Source.REMOVE;
        });

        terminated(call.account.bare_jid, null, reason_text);
    }

    public void mute_own_audio(bool mute) {
        we_should_send_audio = !mute;
        foreach (PeerState peer in peers.values) {
            peer.mute_own_audio(mute);
        }
    }

    public void mute_own_video(bool mute) {
        we_should_send_video = !mute;
        foreach (PeerState peer in peers.values) {
            peer.mute_own_video(mute);
        }
    }

    public bool should_we_send_video() {
        return we_should_send_video;
    }

    public async void invite_to_call(Jid invitee) {
        if (this.group_call == null) yield convert_into_group_call();
        if (this.group_call == null) return;

        // Don't invite if call is already at capacity
        if (peers.size >= MAX_MUJI_PEERS) {
            debug("[%s] Not inviting %s — call already at max peers (%d/%d)", call.account.bare_jid.to_string(), invitee.to_string(), peers.size, MAX_MUJI_PEERS);
            return;
        }

        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream == null) return;

        debug("[%s] Inviting to muji call %s", call.account.bare_jid.to_string(), invitee.to_string());
        yield stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).change_affiliation(stream, group_call.muc_jid, invitee, null, "owner");
        stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_muji_propose(stream, cim_call_id, invitee, group_call.muc_jid, we_should_send_video, "chat");

        // Cancel any existing invite timeout for this invitee (re-invite scenario)
        if (invite_timeout_ids.has_key(invitee)) {
            Source.remove(invite_timeout_ids[invitee]);
            invite_timeout_ids.unset(invitee);
        }

        // If the peer hasn't joined within 60s, retract the invite and remove affiliation
        uint timeout_id = Timeout.add_seconds(60, () => {
            bool contains_peer = false;
            foreach (Jid peer in peers.keys) {
                if (peer.equals_bare(invitee)) {
                    contains_peer = true;
                }
            }

            if (!contains_peer) {
                debug("[%s] Retracting invite to %s from %s", call.account.bare_jid.to_string(), group_call.muc_jid.to_string(), invitee.to_string());
                XmppStream? current_stream = stream_interactor.get_stream(call.account);
                if (current_stream != null) {
                    current_stream.get_module<Xep.CallInvites.Module>(Xep.CallInvites.Module.IDENTITY).send_retract(current_stream, invitee, cim_call_id, "chat");
                    current_stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).change_affiliation.begin(current_stream, group_call.muc_jid, invitee, null, "none");
                }
            }
            invite_timeout_ids.unset(invitee);
            return false;
        });
        invite_timeout_ids[invitee] = timeout_id;
    }

    public Plugins.MediaDevice? get_microphone_device() {
        if (selected_microphone_device == null) {
            if (!peers.is_empty) {
                var audio_stream = peers.values.to_array()[0].get_audio_stream();
                selected_microphone_device = call_plugin.get_device(audio_stream, false);
            }
            if (selected_microphone_device == null) {
                selected_microphone_device = call_plugin.get_preferred_device("audio", false);
            }
        }
        return selected_microphone_device;
    }

    public Plugins.MediaDevice? get_speaker_device() {
        if (selected_speaker_device == null) {
            if (!peers.is_empty) {
                var audio_stream = peers.values.to_array()[0].get_audio_stream();
                selected_speaker_device = call_plugin.get_device(audio_stream, true);
            }
            if (selected_speaker_device == null) {
                selected_speaker_device = call_plugin.get_preferred_device("audio", true);
            }
        }
        return selected_speaker_device;
    }

    public Plugins.MediaDevice? get_video_device() {
        if (selected_video_device == null) {
            if (!peers.is_empty) {
                var video_stream = peers.values.to_array()[0].get_video_stream();
                selected_video_device = call_plugin.get_device(video_stream, false);
            }
            if (selected_video_device == null) {
                selected_video_device = call_plugin.get_preferred_device("video", false);
            }
        }
        return selected_video_device;
    }

    public void set_audio_device(Plugins.MediaDevice? device) {
        if (device.incoming) {
            selected_speaker_device = device;
        } else {
            selected_microphone_device = device;
        }
        foreach (PeerState peer_state in peers.values) {
            call_plugin.set_device(peer_state.get_audio_stream(), device);
        }
    }

    public void set_video_device(Plugins.MediaDevice? device) {
        selected_video_device = device;
        foreach (PeerState peer_state in peers.values) {
            call_plugin.set_device(peer_state.get_video_stream(), device);
        }
    }

    internal void rename_peer(Jid from_jid, Jid to_jid) {
        debug("[%s] Renaming %s to %s exists %s", call.account.bare_jid.to_string(), from_jid.to_string(), to_jid.to_string(), peers.has_key(from_jid).to_string());
        PeerState? peer_state = peers[from_jid];
        if (peer_state == null) return;

        // Adjust the internal mapping of this `PeerState` object
        peers.unset(from_jid);
        peers[to_jid] = peer_state;
        peer_state.jid = to_jid;
    }

    private void on_call_terminated(Jid who_terminated, bool we_terminated, string? reason_name, string? reason_text) {
        // Cancel any pending timeouts (establishing, MUJI empty MUC, invite)
        cancel_all_timeouts();

        // Release cached device references so that the RTP plugin's
        // Gst.Device / GstDeviceProvider (and its PipeWire connection)
        // can be finalized after destroy_call_pipe().
        selected_microphone_device = null;
        selected_speaker_device = null;
        selected_video_device = null;

        if (call.state == Call.State.RINGING || call.state == Call.State.IN_PROGRESS || call.state == Call.State.ESTABLISHING) {
            call.end_time = new DateTime.now_utc();
        }
        if (call.state == Call.State.IN_PROGRESS) {
            call.state = Call.State.ENDED;
        } else if (call.state == Call.State.RINGING || call.state == Call.State.ESTABLISHING) {
            if (reason_name == Xep.Jingle.ReasonElement.DECLINE) {
                call.state = Call.State.DECLINED;
            } else {
                call.state = Call.State.FAILED;
            }
        }

        terminated(who_terminated, reason_name, reason_text);
    }

    private void connect_peer_signals(PeerState peer_state) {
        peers[peer_state.jid] = peer_state;

        this.bind_property("we-should-send-audio", peer_state, "we-should-send-audio", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        this.bind_property("we-should-send-video", peer_state, "we-should-send-video", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        this.bind_property("group-call", peer_state, "group-call", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        peer_state.stream_created.connect((peer, media) => { on_peer_stream_created(peer, media); });
        peer_state.session_terminated.connect((we_terminated, reason_name, reason_text) => {
            debug("[%s] Peer left %s: %s %s (%i peers remaining)", call.account.bare_jid.to_string(), reason_text ?? "", reason_name ?? "", peer_state.jid.to_string(), peers.size);
            handle_peer_left(peer_state, we_terminated, reason_name, reason_text);
        });
    }

    public async bool can_convert_into_groupcall() {
        if (peers.size == 0) return false;
        Jid peer = peers.keys.to_array()[0];
        bool peer_has_feature = yield stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY).has_feature(call.account, peer, Xep.Muji.NS_URI);
        bool can_initiate = stream_interactor.get_module<Calls>(Calls.IDENTITY).can_initiate_groupcall(call.account);
        return peer_has_feature && can_initiate;
    }

    public async void convert_into_group_call() {
        // Guard: prevent async race — only one conversion at a time
        if (group_call_converting) {
            debug("[%s] convert_into_group_call already in progress, skipping", call.account.bare_jid.to_string());
            return;
        }
        group_call_converting = true;

        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream == null) { group_call_converting = false; return; }

        Jid? muc_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).default_muc_server[call.account];
        if (muc_jid == null) {
            warning("Failed to initiate group call: MUC server not known.");
            group_call_converting = false;
            return;
        }

        if (cim_call_id == null) cim_call_id = Xmpp.random_uuid();
        try {
            muc_jid = new Jid("%08x@".printf(Random.next_int()) + muc_jid.to_string()); // TODO longer?
        } catch (Xmpp.InvalidJidError e) {
            warning("Failed to create MUC JID for group call: %s", e.message);
            group_call_converting = false;
            return;
        }

        debug("[%s] Converting call to groupcall %s", call.account.bare_jid.to_string(), muc_jid.to_string());
        yield join_group_call(muc_jid);

        Xep.DataForms.DataForm? data_form = yield stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_config_form(call.account, muc_jid);
        if (data_form == null) return;

        foreach (Xep.DataForms.DataForm.Field field in data_form.fields) {
            switch (field.var) {
                case "muc#roomconfig_allowinvites":
                    if (field.type_ == Xep.DataForms.DataForm.Type.BOOLEAN) {
                        ((Xep.DataForms.DataForm.BooleanField) field).value = true;
                    }
                    break;
                case "muc#roomconfig_persistentroom":
                    if (field.type_ == Xep.DataForms.DataForm.Type.BOOLEAN) {
                        ((Xep.DataForms.DataForm.BooleanField) field).value = false;
                    }
                    break;
                case "muc#roomconfig_membersonly":
                    if (field.type_ == Xep.DataForms.DataForm.Type.BOOLEAN) {
                        ((Xep.DataForms.DataForm.BooleanField) field).value = true;
                    }
                    break;
                case "muc#roomconfig_whois":
                    if (field.type_ == Xep.DataForms.DataForm.Type.LIST_SINGLE) {
                        ((Xep.DataForms.DataForm.ListSingleField) field).value = "anyone";
                    }
                    break;
            }
        }
        yield stream_interactor.get_module<MucManager>(MucManager.IDENTITY).set_config_form(call.account, muc_jid, data_form);

        foreach (Jid peer_jid in peers.keys) {
            debug("[%s] Group call inviting %s", call.account.bare_jid.to_string(), peer_jid.to_string());
            yield invite_to_call(peer_jid);
        }
    }

    public async void join_group_call(Jid muc_jid) {
        debug("[%s] Joining group call %s", call.account.bare_jid.to_string(), muc_jid.to_string());
        XmppStream stream = stream_interactor.get_stream(call.account);
        if (stream == null) return;

        this.group_call = yield stream.get_module<Xep.Muji.Module>(Xep.Muji.Module.IDENTITY).join_call(stream, muc_jid, we_should_send_video);
        if (this.group_call == null) {
            warning("[%s] Couldn't join MUJI MUC", call.account.bare_jid.to_string());
            return;
        }

        this.group_call.peer_joined.connect((jid) => {
            debug("[%s] Group call peer joined: %s", call.account.bare_jid.to_string(), jid.to_string());

            // First peer joined: cancel empty-MUC timeout
            if (muji_empty_muc_timeout_id != 0) {
                Source.remove(muji_empty_muc_timeout_id);
                muji_empty_muc_timeout_id = 0;
            }

            // Newly joined peers have to call us, not the other way round
            // Maybe they called us already. Accept the call.
            // (Except for the first peer, we already have a connection to that one.)
            if (peers.has_key(jid)) {
                if (!peers[jid].first_peer) {
                    peers[jid].accept();
                }
                // else: Connection to first peer already active
            } else {
                var peer_state = new PeerState(jid, call, this, stream_interactor);
                peer_state.waiting_for_inbound_muji_connection = true;
                debug("[%s] Waiting for call from %s", call.account.bare_jid.to_string(), jid.to_string());
                add_peer(peer_state);
            }
        });

        this.group_call.peer_left.connect((jid) => {
            debug("[%s] Group call peer left: %s", call.account.bare_jid.to_string(), jid.to_string());
            PeerState? peer_state = peers[jid];
            if (peer_state == null) return;
            peer_state.end(Xep.Jingle.ReasonElement.CANCEL, "Peer left the MUJI MUC");
            handle_peer_left(peer_state, false, Xep.Jingle.ReasonElement.CANCEL, "Peer left the MUJI MUC");
        });

        this.group_call.codecs_changed.connect((payload_types) => {
            if (payload_types.is_empty) {
                warning("[%s] MUJI codec intersection is now EMPTY — no common codecs with all peers", call.account.bare_jid.to_string());
            } else {
                var codec_names = new Gee.ArrayList<string>();
                foreach (var pt in payload_types) {
                    codec_names.add(pt.name ?? "unknown");
                }
                debug("[%s] MUJI codec intersection updated: %s", call.account.bare_jid.to_string(), string.joinv(", ", codec_names.to_array()));
            }
        });

        if (group_call.peers_to_connect_to.size > MAX_MUJI_PEERS) {
            debug("[%s] Call full: %d peers (max %d)", call.account.bare_jid.to_string(), group_call.peers_to_connect_to.size, MAX_MUJI_PEERS);
            end(CALL_FULL_REASON);
            return;
        }

        // Call all peers that are in the room already
        foreach (Jid peer_jid in group_call.peers_to_connect_to) {
            // Don't establish connection if we have one already (the person that invited us to the call)
            if (peers.has_key(peer_jid)) continue;

            debug("[%s] Calling %s because they were in the MUC already", call.account.bare_jid.to_string(), peer_jid.to_string());

            PeerState peer_state = new PeerState(peer_jid, call, this, stream_interactor);
            add_peer(peer_state);
            peer_state.call_resource.begin(peer_jid);
        }

        // Start MUJI empty-MUC timeout: if no peers appear, end the call
        // Initiator gets more time (90s) because peers need to receive invite + join
        // Receiver gets 30s — if MUC is empty, the initiator probably left
        if (peers.is_empty) {
            uint muji_timeout = (call.direction == Call.DIRECTION_OUTGOING) ? 90 : 30;
            start_muji_empty_muc_timeout(muji_timeout);
        }

        debug("[%s] Finished joining MUJI muc %s", call.account.bare_jid.to_string(), muc_jid.to_string());
    }

    // --- Timeout management: 1:1 and MUJI are completely separate ---

    public void start_establishing_timeout(uint seconds) {
        if (establishing_timeout_id != 0) Source.remove(establishing_timeout_id);
        establishing_timeout_id = Timeout.add_seconds(seconds, () => {
            if (call.state == Call.State.ESTABLISHING || call.state == Call.State.RINGING) {
                debug("[%s] Establishing timeout (%us) expired", call.account.bare_jid.to_string(), seconds);
                call.state = Call.State.MISSED;
                terminated(call.account.bare_jid, null, null);
            }
            establishing_timeout_id = 0;
            return false;
        });
    }

    private void start_muji_empty_muc_timeout(uint seconds) {
        if (muji_empty_muc_timeout_id != 0) Source.remove(muji_empty_muc_timeout_id);
        muji_empty_muc_timeout_id = Timeout.add_seconds(seconds, () => {
            if (peers.is_empty && group_call != null) {
                debug("[%s] MUJI empty MUC timeout (%us) expired", call.account.bare_jid.to_string(), seconds);
                end("No participants joined the group call");
            }
            muji_empty_muc_timeout_id = 0;
            return false;
        });
    }

    private void cancel_all_timeouts() {
        if (establishing_timeout_id != 0) {
            Source.remove(establishing_timeout_id);
            establishing_timeout_id = 0;
        }
        if (muji_empty_muc_timeout_id != 0) {
            Source.remove(muji_empty_muc_timeout_id);
            muji_empty_muc_timeout_id = 0;
        }
        foreach (uint tid in invite_timeout_ids.values) {
            Source.remove(tid);
        }
        invite_timeout_ids.clear();
    }

    private void handle_peer_left(PeerState peer_state, bool we_terminated, string? reason_name, string? reason_text) {
        if (!peers.has_key(peer_state.jid)) return;
        peers.unset(peer_state.jid);

        if (peers.is_empty) {
            if (group_call != null) {
                Xep.Muji.GroupCall gc = group_call;
                group_call = null;
                XmppStream? stream = stream_interactor.get_stream(call.account);
                if (stream != null) {
                    // Destroy the ephemeral MUC, falling back to just leaving
                    var flag = stream.get_flag(Xep.Muji.Flag.IDENTITY);
                    if (flag != null) flag.calls.unset(gc.muc_jid);
                    stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).destroy_room.begin(
                        stream, gc.muc_jid, "Call ended", null, (_, res) => {
                        try {
                            stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).destroy_room.end(res);
                        } catch (Error e) {
                            debug("Could not destroy MUJI MUC %s: %s", gc.muc_jid.to_string(), e.message);
                            stream.get_module<Xep.Muc.Module>(Xep.Muc.Module.IDENTITY).exit(stream, gc.muc_jid);
                        }
                    });
                }
                // Remove the ephemeral MUJI conversation from the sidebar
                Conversation? muji_conv = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY)
                    .get_conversation(gc.muc_jid, call.account, Conversation.Type.GROUPCHAT);
                if (muji_conv != null) {
                    stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).close_conversation(muji_conv);
                }
                on_call_terminated(peer_state.jid, we_terminated, null, "All participants have left the call");
            } else {
                on_call_terminated(peer_state.jid, we_terminated, reason_name, reason_text);
            }
        } else {
            peer_left(peer_state.jid, peer_state, reason_name, reason_text);
        }
    }
}
