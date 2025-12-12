using Gee;
using Xmpp;
using Xmpp.Xep;


public class Dino.Plugins.Ice.TransportParameters : JingleIceUdp.IceUdpTransportParameters {
    private Nice.Agent agent;
    private uint stream_id;
    private bool we_want_connection;
    private bool remote_credentials_set;
    private Map<uint8, DatagramConnection> connections = new HashMap<uint8, DatagramConnection>();
    private DtlsSrtp.Handler? dtls_srtp_handler;
    private MainContext thread_context;
    private MainLoop thread_loop;
    
    // Signal handler IDs for proper cleanup
    private ulong candidate_gathering_done_id;
    private ulong initial_binding_request_received_id;
    private ulong component_state_changed_id;
    private ulong new_selected_pair_full_id;
    private ulong new_candidate_full_id;

    private class DatagramConnection : Jingle.DatagramConnection {
        private Nice.Agent agent;
        private DtlsSrtp.Handler? dtls_srtp_handler;
        private uint stream_id;
        private ulong datagram_received_id;

        public DatagramConnection(Nice.Agent agent, DtlsSrtp.Handler? dtls_srtp_handler, uint stream_id, uint8 component_id) {
            this.agent = agent;
            this.dtls_srtp_handler = dtls_srtp_handler;
            this.stream_id = stream_id;
            this.component_id = component_id;
            this.datagram_received_id = this.datagram_received.connect((datagram) => {
                bytes_received += datagram.length;
            });
        }

        public override async void terminate(bool we_terminated, string? reason_string = null, string? reason_text = null) {
            yield base.terminate(we_terminated, reason_string, reason_text);
            this.disconnect(datagram_received_id);
            agent = null;
            dtls_srtp_handler = null;
        }

        private Gee.LinkedList<Bytes>? pending_packets = null;
        private bool dtls_ready_notified = false;
        private int64 last_eagain_warning = 0;
        private int eagain_count = 0;

        public override void send_datagram(Bytes datagram) {
            if (this.agent != null && is_component_ready(agent, stream_id, component_id)) {
                try {
                    if (dtls_srtp_handler != null) {
                        // If DTLS is not ready yet, buffer the packets
                        if (!dtls_srtp_handler.ready) {
                            if (pending_packets == null) {
                                pending_packets = new Gee.LinkedList<Bytes>();
                            }
                            // Limit buffer size to avoid memory issues
                            if (pending_packets.size < 100) {
                                pending_packets.add(datagram);
                                debug("send_datagram: DTLS not ready, buffering packet (%d pending)", pending_packets.size);
                            } else {
                                debug("send_datagram: DTLS not ready, buffer full, dropping packet");
                            }
                            
                            // Set up a one-time notification for when DTLS becomes ready
                            if (!dtls_ready_notified) {
                                dtls_ready_notified = true;
                                check_dtls_ready.begin();
                            }
                            return;
                        }
                        
                        uint8[] encrypted_data = dtls_srtp_handler.process_outgoing_data(component_id, datagram.get_data());
                        if (encrypted_data == null) {
                            debug("send_datagram: encrypted_data is null, dropping packet");
                            return;
                        }
                        GLib.OutputVector vector = { encrypted_data, encrypted_data.length };
                        GLib.OutputVector[] vectors = { vector };
                        Nice.OutputMessage message = { vectors };
                        Nice.OutputMessage[] messages = { message };
                        agent.send_messages_nonblocking(stream_id, component_id, messages);
                    } else {
                        GLib.OutputVector vector = { datagram.get_data(), datagram.get_size() };
                        GLib.OutputVector[] vectors = { vector };
                        Nice.OutputMessage message = { vectors };
                        Nice.OutputMessage[] messages = { message };
                        agent.send_messages_nonblocking(stream_id, component_id, messages);
                    }
                    bytes_sent += datagram.length;
                    // Reset EAGAIN counter on successful send
                    eagain_count = 0;
                } catch (GLib.Error e) {
                    // EAGAIN (Resource temporarily unavailable) is common during connection setup
                    // Don't spam the log, just count them and log periodically
                    if (e.message.contains("nicht verfügbar") || e.message.contains("unavailable") || e.code == 11) {
                        eagain_count++;
                        int64 now = GLib.get_monotonic_time();
                        // Log only once per second maximum
                        if (now - last_eagain_warning > 1000000) {
                            if (eagain_count > 1) {
                                debug("ICE send_datagram: %d packets dropped (resource unavailable) stream %u component %u", eagain_count, stream_id, component_id);
                            }
                            last_eagain_warning = now;
                            eagain_count = 0;
                        }
                    } else {
                        warning("%s while send_datagram stream %u component %u", e.message, stream_id, component_id);
                    }
                }
            }
        }
        
        private async void check_dtls_ready() {
            // Poll until DTLS is ready, then send buffered packets
            while (dtls_srtp_handler != null && !dtls_srtp_handler.ready) {
                Timeout.add(10, check_dtls_ready.callback);
                yield;
            }
            
            if (dtls_srtp_handler != null && pending_packets != null) {
                debug("DTLS now ready, discarding %d buffered packets (waiting for new keyframe)", pending_packets.size);
                // Don't send old packets - they're likely outdated video frames
                // Instead, clear the buffer and let new keyframes come through
                pending_packets.clear();
                pending_packets = null;
            }
            
            // Mark this connection as ready now that DTLS is complete
            // This will trigger on_rtp_ready() which requests a keyframe
            if (agent != null && is_component_ready(agent, stream_id, component_id) && !this.ready) {
                debug("DTLS ready, marking connection as ready for stream %u component %u", stream_id, component_id);
                this.ready = true;
            }
        }
    }

    public TransportParameters(Nice.Agent agent, DtlsSrtp.CredentialsCapsule? credentials, Xep.ExternalServiceDiscovery.Service? turn_service, string? turn_ip, uint8 components, Jid local_full_jid, Jid peer_full_jid, StanzaNode? node = null) {
        base(components, local_full_jid, peer_full_jid, node);
        this.we_want_connection = (node == null);
        this.agent = agent;

        if (this.peer_fingerprint != null || !incoming) {
            dtls_srtp_handler = setup_dtls(this, credentials);
            own_fingerprint = dtls_srtp_handler.own_fingerprint;
            if (incoming) {
                own_setup = "active";
                dtls_srtp_handler.mode = DtlsSrtp.Mode.CLIENT;
                dtls_srtp_handler.peer_fingerprint = peer_fingerprint;
                dtls_srtp_handler.peer_fp_algo = peer_fp_algo;
            } else {
                own_setup = "actpass";
                dtls_srtp_handler.mode = DtlsSrtp.Mode.SERVER;
                dtls_srtp_handler.setup_dtls_connection.begin((_, res) => {
                    var content_encryption = dtls_srtp_handler.setup_dtls_connection.end(res);
                    if (content_encryption != null) {
                        this.content.encryptions[content_encryption.encryption_ns] = content_encryption;
                    }
                });
            }
        }

        candidate_gathering_done_id = agent.candidate_gathering_done.connect(on_candidate_gathering_done);
        initial_binding_request_received_id = agent.initial_binding_request_received.connect(on_initial_binding_request_received);
        component_state_changed_id = agent.component_state_changed.connect(on_component_state_changed);
        new_selected_pair_full_id = agent.new_selected_pair_full.connect(on_new_selected_pair_full);
        new_candidate_full_id = agent.new_candidate_full.connect(on_new_candidate);

        agent.controlling_mode = !incoming;
        stream_id = agent.add_stream(components);
        thread_context = new MainContext();
        new Thread<void*>(@"ice-thread-$stream_id", () => {
            thread_context.push_thread_default();
            thread_loop = new MainLoop(thread_context, false);
            thread_loop.run();
            thread_context.pop_thread_default();
            return null;
        });

        if (turn_ip != null) {
            Nice.RelayType relay_type = Nice.RelayType.UDP;
            if (turn_service.transport == "tcp") {
                relay_type = Nice.RelayType.TCP;
            } else if (turn_service.transport == "tls") {
                relay_type = Nice.RelayType.TLS;
            }

            for (uint8 component_id = 1; component_id <= components; component_id++) {
                agent.set_relay_info(stream_id, component_id, turn_ip, turn_service.port, turn_service.username, turn_service.password, relay_type);
                debug("TURN info (component %i) %s:%u transport:%s", component_id, turn_ip, turn_service.port, turn_service.transport);
            }
        }
        string ufrag;
        string pwd;
        agent.get_local_credentials(stream_id, out ufrag, out pwd);
        init(ufrag, pwd);

        for (uint8 component_id = 1; component_id <= components; component_id++) {
            // We don't properly get local candidates before this call
            agent.attach_recv(stream_id, component_id, thread_context, on_recv);
        }

        agent.gather_candidates(stream_id);
    }

    private static DtlsSrtp.Handler setup_dtls(TransportParameters tp, DtlsSrtp.CredentialsCapsule credentials) {
        var weak_self = WeakRef(tp);
        DtlsSrtp.Handler dtls_srtp = new DtlsSrtp.Handler.with_cert(credentials);
        dtls_srtp.send_data.connect((data) => {
            TransportParameters self = (TransportParameters) weak_self.get();
            if (self != null) self.agent.send(self.stream_id, 1, data);
        });
        return dtls_srtp;
    }

    private void on_candidate_gathering_done(uint stream_id) {
        if (stream_id != this.stream_id) return;
        debug("on_candidate_gathering_done in %u", stream_id);

        for (uint8 i = 1; i <= components; i++) {
            foreach (unowned Nice.Candidate nc in agent.get_local_candidates(stream_id, i)) {
                if (nc.transport == Nice.CandidateTransport.UDP) {
                    JingleIceUdp.Candidate? candidate = candidate_to_jingle(nc);
                    if (candidate == null) continue;
                    debug("Local candidate summary: %s", agent.generate_local_candidate_sdp(nc));
                }
            }
        }
    }

    private void on_new_candidate(Nice.Candidate nc) {
        if (nc.stream_id != stream_id) return;
        JingleIceUdp.Candidate? candidate = candidate_to_jingle(nc);
        if (candidate == null) return;

        if (nc.transport == Nice.CandidateTransport.UDP) {
            // Execution was in the agent thread before
            add_local_candidate_threadsafe(candidate);
        }
    }

    private bool bytes_equal(uint8[] a1, uint8[] a2) {
        return a1.length == a2.length && Memory.cmp(a1, a2, a1.length) == 0;
    }

    public override void handle_transport_accept(StanzaNode transport) throws Jingle.IqError {
        debug("on_transport_accept from %s", peer_full_jid.to_string());
        base.handle_transport_accept(transport);

        if (dtls_srtp_handler != null && peer_fingerprint != null) {
            if (dtls_srtp_handler.peer_fingerprint != null) {
                if (!bytes_equal(dtls_srtp_handler.peer_fingerprint, peer_fingerprint)) {
                    warning("Tried to replace certificate fingerprint mid use. We don't allow that.");
                    peer_fingerprint = dtls_srtp_handler.peer_fingerprint;
                    peer_fp_algo = dtls_srtp_handler.peer_fp_algo;
                }
            } else {
                dtls_srtp_handler.peer_fingerprint = peer_fingerprint;
                dtls_srtp_handler.peer_fp_algo = peer_fp_algo;
            }
            debug("DTLS: peer_setup='%s', our own_setup='%s'", peer_setup ?? "null", own_setup ?? "null");
            if (peer_setup == "passive") {
                debug("DTLS: Switching to CLIENT mode because peer is passive");
                dtls_srtp_handler.mode = DtlsSrtp.Mode.CLIENT;
                dtls_srtp_handler.stop_dtls_connection();
                dtls_srtp_handler.setup_dtls_connection.begin((_, res) => {
                    var content_encryption = dtls_srtp_handler.setup_dtls_connection.end(res);
                    if (content_encryption != null) {
                        this.content.encryptions[content_encryption.encryption_ns] = content_encryption;
                    }
                });
            } else if (peer_setup == "active") {
                debug("DTLS: Staying as SERVER mode because peer is active");
            } else if (peer_setup == "actpass") {
                debug("DTLS: Peer is actpass - we decide. We're %s", own_setup ?? "null");
                // If peer is actpass and we're actpass (initiator), we stay server
                // If peer is actpass and we're active, we're client
            } else {
                debug("DTLS: Unknown or null peer_setup, staying as current mode");
            }
        } else {
            dtls_srtp_handler = null;
        }
    }

    public override void handle_transport_info(StanzaNode transport) throws Jingle.IqError {
        debug("on_transport_info from %s", peer_full_jid.to_string());
        base.handle_transport_info(transport);

        if (dtls_srtp_handler != null && peer_fingerprint != null) {
            if (dtls_srtp_handler.peer_fingerprint != null) {
                if (!bytes_equal(dtls_srtp_handler.peer_fingerprint, peer_fingerprint)) {
                    warning("Tried to replace certificate fingerprint mid use. We don't allow that.");
                    peer_fingerprint = dtls_srtp_handler.peer_fingerprint;
                    peer_fp_algo = dtls_srtp_handler.peer_fp_algo;
                }
            } else {
                dtls_srtp_handler.peer_fingerprint = peer_fingerprint;
                dtls_srtp_handler.peer_fp_algo = peer_fp_algo;
            }
        }

        if (!we_want_connection) return;

        if (remote_ufrag != null && remote_pwd != null && !remote_credentials_set) {
            agent.set_remote_credentials(stream_id, remote_ufrag, remote_pwd);
            remote_credentials_set = true;
        }
        for (uint8 i = 1; i <= components; i++) {
            SList<Nice.Candidate> candidates = new SList<Nice.Candidate>();
            foreach (JingleIceUdp.Candidate candidate in remote_candidates) {
                if (candidate.component == i) {
                    candidates.append(candidate_to_nice(candidate));
                }
            }
            int new_candidates = agent.set_remote_candidates(stream_id, i, candidates);
            debug("Updated to %i remote candidates for candidate %u via transport info", new_candidates, i);
        }
    }

    public override void create_transport_connection(XmppStream stream, Jingle.Content content) {
        debug("create_transport_connection: %s", content.session.sid);
        debug("local_credentials: %s %s", local_ufrag, local_pwd);
        debug("remote_credentials: %s %s", remote_ufrag, remote_pwd);
        debug("expected incoming credentials: %s %s", local_ufrag + ":" + remote_ufrag, local_pwd);
        debug("expected outgoing credentials: %s %s", remote_ufrag + ":" + local_ufrag, remote_pwd);

        we_want_connection = true;

        if (remote_ufrag != null && remote_pwd != null && !remote_credentials_set) {
            agent.set_remote_credentials(stream_id, remote_ufrag, remote_pwd);
            remote_credentials_set = true;
        }
        for (uint8 i = 1; i <= components; i++) {
            SList<Nice.Candidate> candidates = new SList<Nice.Candidate>();
            foreach (JingleIceUdp.Candidate candidate in remote_candidates) {
                if (candidate.ip.has_prefix("fe80::")) continue;
                if (candidate.component == i) {
                    candidates.append(candidate_to_nice(candidate));
                    debug("remote candidate: %s", agent.generate_local_candidate_sdp(candidate_to_nice(candidate)));
                }
            }
            int new_candidates = agent.set_remote_candidates(stream_id, i, candidates);
            debug("Initiated component %u with %i remote candidates", i, new_candidates);

            connections[i] = new DatagramConnection(agent, dtls_srtp_handler, stream_id, i);
            content.set_transport_connection(connections[i], i);
        }

        base.create_transport_connection(stream, content);
    }

    private void on_component_state_changed(uint stream_id, uint component_id, uint state) {
        if (stream_id != this.stream_id) return;
        debug("stream %u component %u state changed to %s", stream_id, component_id, agent.get_component_state(stream_id, component_id).to_string());
        may_consider_ready(stream_id, component_id);
        if (incoming && dtls_srtp_handler != null && !dtls_srtp_handler.ready && is_component_ready(agent, stream_id, component_id) && dtls_srtp_handler.mode == DtlsSrtp.Mode.CLIENT) {
            dtls_srtp_handler.setup_dtls_connection.begin((_, res) => {
                Jingle.ContentEncryption? encryption = dtls_srtp_handler.setup_dtls_connection.end(res);
                if (encryption != null) {
                    this.content.encryptions[encryption.encryption_ns] = encryption;
                }
            });
        }
    }

    private void may_consider_ready(uint stream_id, uint component_id) {
        if (stream_id != this.stream_id) return;
        if (connections.has_key((uint8) component_id) && !connections[(uint8)component_id].ready && is_component_ready(agent, stream_id, component_id) && (dtls_srtp_handler == null || dtls_srtp_handler.ready)) {
            connections[(uint8)component_id].ready = true;
        }
    }

    private void on_initial_binding_request_received(uint stream_id) {
        if (stream_id != this.stream_id) return;
        debug("initial_binding_request_received");
    }

    private void on_new_selected_pair_full(uint stream_id, uint component_id, Nice.Candidate p1, Nice.Candidate p2) {
        if (stream_id != this.stream_id) return;
        debug("new_selected_pair_full %u [%s, %s]", component_id, agent.generate_local_candidate_sdp(p1), agent.generate_local_candidate_sdp(p2));
    }

    private void on_recv(Nice.Agent agent, uint stream_id, uint component_id, uint8[] data) {
        if (stream_id != this.stream_id) return;
        uint8[] decrypt_data = null;
        if (dtls_srtp_handler != null) {
            try {
                decrypt_data = dtls_srtp_handler.process_incoming_data(component_id, data);
                if (decrypt_data == null) return;
            } catch (Crypto.Error e) {
                warning("%s while on_recv stream %u component %u", e.message, stream_id, component_id);
                return;
            }
        }
        may_consider_ready(stream_id, component_id);
        if (connections.has_key((uint8) component_id)) {
            if (!connections[(uint8) component_id].ready) {
                debug("on_recv stream %u component %u when state %s", stream_id, component_id, agent.get_component_state(stream_id, component_id).to_string());
            }
            connections[(uint8) component_id].datagram_received(new Bytes(decrypt_data ?? data));
        } else {
            debug("on_recv stream %u component %u length %u", stream_id, component_id, data.length);
        }
    }

    private static Nice.Candidate candidate_to_nice(JingleIceUdp.Candidate c) {
        Nice.CandidateType type;
        switch (c.type_) {
            case JingleIceUdp.Candidate.Type.HOST: type = Nice.CandidateType.HOST; break;
            case JingleIceUdp.Candidate.Type.PRFLX: type = Nice.CandidateType.PEER_REFLEXIVE; break;
            case JingleIceUdp.Candidate.Type.RELAY: type = Nice.CandidateType.RELAYED; break;
            case JingleIceUdp.Candidate.Type.SRFLX: type = Nice.CandidateType.SERVER_REFLEXIVE; break;
            default: assert_not_reached();
        }

        Nice.Candidate candidate = new Nice.Candidate(type);
        candidate.component_id = c.component;
        char[] foundation = new char[Nice.CANDIDATE_MAX_FOUNDATION];
        Memory.copy(foundation, c.foundation.data, size_t.min(c.foundation.length, Nice.CANDIDATE_MAX_FOUNDATION - 1));
        candidate.foundation = foundation;
        candidate.addr = Nice.Address();
        candidate.addr.init();
        candidate.addr.set_from_string(c.ip);
        candidate.addr.set_port(c.port);
        candidate.priority = c.priority;
        if (c.rel_addr != null) {
            candidate.base_addr = Nice.Address();
            candidate.base_addr.init();
            candidate.base_addr.set_from_string(c.rel_addr);
            candidate.base_addr.set_port(c.rel_port);
        }
        candidate.transport = Nice.CandidateTransport.UDP;
        return candidate;
    }

    private static JingleIceUdp.Candidate? candidate_to_jingle(Nice.Candidate nc) {
        JingleIceUdp.Candidate candidate = new JingleIceUdp.Candidate();
        switch (nc.type) {
            case Nice.CandidateType.HOST: candidate.type_ = JingleIceUdp.Candidate.Type.HOST; break;
            case Nice.CandidateType.PEER_REFLEXIVE: candidate.type_ = JingleIceUdp.Candidate.Type.PRFLX; break;
            case Nice.CandidateType.RELAYED: candidate.type_ = JingleIceUdp.Candidate.Type.RELAY; break;
            case Nice.CandidateType.SERVER_REFLEXIVE: candidate.type_ = JingleIceUdp.Candidate.Type.SRFLX; break;
            default: assert_not_reached();
        }
        candidate.component = (uint8) nc.component_id;
        candidate.foundation = ((string)nc.foundation).dup();
        candidate.generation = 0;
        candidate.id = Random.next_int().to_string("%08x"); // TODO

        char[] res = new char[NICE_ADDRESS_STRING_LEN];
        nc.addr.to_string(res);
        candidate.ip = (string) res;
        candidate.network = 0; // TODO
        candidate.port = (uint16) nc.addr.get_port();
        candidate.priority = nc.priority;
        candidate.protocol = "udp";
        if (nc.base_addr.is_valid() && !nc.base_addr.equal(nc.addr)) {
            res = new char[NICE_ADDRESS_STRING_LEN];
            nc.base_addr.to_string(res);
            candidate.rel_addr = (string) res;
            candidate.rel_port = (uint16) nc.base_addr.get_port();
        }
        if (candidate.ip.has_prefix("fe80::")) return null;

        return candidate;
    }

    // Cleanup method called explicitly before termination
    // This releases TURN allocations BEFORE the agent is destroyed
    public override void cleanup() {
        debug("TransportParameters cleanup: cleaning up agent and stream %u", stream_id);
        if (agent != null) {
            // Disconnect signal handlers BEFORE removing the stream or releasing the agent
            // Use SignalHandler.is_connected() to avoid "has no handler" warnings
            if (candidate_gathering_done_id != 0 && SignalHandler.is_connected(agent, candidate_gathering_done_id)) {
                agent.disconnect(candidate_gathering_done_id);
            }
            candidate_gathering_done_id = 0;
            
            if (initial_binding_request_received_id != 0 && SignalHandler.is_connected(agent, initial_binding_request_received_id)) {
                agent.disconnect(initial_binding_request_received_id);
            }
            initial_binding_request_received_id = 0;
            
            if (component_state_changed_id != 0 && SignalHandler.is_connected(agent, component_state_changed_id)) {
                agent.disconnect(component_state_changed_id);
            }
            component_state_changed_id = 0;
            
            if (new_selected_pair_full_id != 0 && SignalHandler.is_connected(agent, new_selected_pair_full_id)) {
                agent.disconnect(new_selected_pair_full_id);
            }
            new_selected_pair_full_id = 0;
            
            if (new_candidate_full_id != 0 && SignalHandler.is_connected(agent, new_candidate_full_id)) {
                agent.disconnect(new_candidate_full_id);
            }
            new_candidate_full_id = 0;
            
            // Remove the stream to stop ICE processing
            if (stream_id != 0) {
                agent.remove_stream(stream_id);
                stream_id = 0;
            }
            
            // Stop the thread loop to release the agent
            if (thread_loop != null) {
                thread_loop.quit();
                thread_loop = null;
            }
            
            // Clear connections
            foreach (var conn in connections.values) {
                conn.terminate.begin(true, null, null);
            }
            connections.clear();
            
            // Release the agent - since we create one per call, it can be freed
            agent = null;
            dtls_srtp_handler = null;
            
            debug("TransportParameters cleanup: agent released");
        }
    }

    public override void dispose() {
        base.dispose();
        // Cleanup should have been called already, but ensure resources are released
        if (agent != null) {
            debug("dispose: agent not cleaned up, doing it now for stream %u", stream_id);
            cleanup();
        }
    }
}
