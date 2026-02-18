using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.BotFeatures {

// Manages XMPP streams for bot accounts.
// In "personal" mode, bots share the user's existing stream.
// In "dedicated" mode, bots have their own XMPP sessions.
public class SessionPool : Object {

    private Dino.Application app;
    private BotRegistry? registry;
    public BotOmemoManager? bot_omemo;

    // Personal mode: bot_id -> Account
    private HashMap<int, Account> personal_bindings = new HashMap<int, Account>();

    // Dedicated mode: bot_id -> own XmppStream
    private HashMap<int, TlsXmppStream> dedicated_streams = new HashMap<int, TlsXmppStream>();
    private HashMap<int, bool> connecting = new HashMap<int, bool>();
    private HashMap<int, BotInfo> bot_infos = new HashMap<int, BotInfo>();

    // Signal fired when a dedicated bot stream is fully ready
    public signal void dedicated_bot_ready(int bot_id, BotInfo bot);

    // Signal fired when a dedicated bot receives a message
    public signal void dedicated_message_received(int bot_id, Xmpp.MessageStanza message);

    public SessionPool(Dino.Application app) {
        this.app = app;
    }

    public void set_registry(BotRegistry registry) {
        this.registry = registry;
    }

    public void set_bot_omemo(BotOmemoManager omemo) {
        this.bot_omemo = omemo;
    }

    // For personal mode: bind a bot to the user's active account
    public void bind_personal(int bot_id, Account account) {
        personal_bindings[bot_id] = account;
    }

    public void unbind(int bot_id) {
        personal_bindings.unset(bot_id);
        disconnect_dedicated(bot_id);
    }

    // Get the XMPP stream for a bot.
    public XmppStream? get_stream(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) {
                account = get_first_active_account();
                if (account != null) {
                    personal_bindings[bot.id] = account;
                }
            }
            if (account != null) {
                return app.stream_interactor.get_stream(account);
            }
        }

        if (bot.mode == "dedicated") {
            // Return existing stream if connected
            if (dedicated_streams.has_key(bot.id)) {
                return dedicated_streams[bot.id];
            }
            // Auto-connect if not yet connected
            if (!connecting.has_key(bot.id) || !connecting[bot.id]) {
                connect_dedicated.begin(bot);
            }
            return null;
        }

        return null;
    }

    // Get a Jid to send from for a bot
    public Jid? get_sender_jid(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) account = get_first_active_account();
            if (account != null) {
                return account.bare_jid;
            }
        }
        // For dedicated mode, the bot has its own JID
        if (bot.jid != null) {
            try {
                return new Jid(bot.jid);
            } catch (Error e) {
                warning("Invalid bot JID: %s", bot.jid);
            }
        }
        return null;
    }

    public Account? get_account_for_bot(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) account = get_first_active_account();
            return account;
        }
        return null;
    }

    // Connect a dedicated bot to XMPP with its own stream
    public async bool connect_dedicated(BotInfo bot) {
        if (bot.jid == null || bot.bot_password == null) {
            warning("SessionPool: Bot %d has no JID or password for dedicated mode", bot.id);
            return false;
        }

        if (connecting.has_key(bot.id) && connecting[bot.id]) {
            return false; // already connecting
        }
        connecting[bot.id] = true;

        // Pre-suppress subscription notification BEFORE connecting, so the
        // subscription request from ejabberd never reaches the systray.
        try {
            Jid suppress_jid = new Jid(bot.jid);
            var presence_mgr = app.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            presence_mgr.suppress_subscription_notification(suppress_jid);
            message("SessionPool: Pre-suppressed subscription for %s", bot.jid);
        } catch (Error e) {
            // non-fatal
        }

        try {
            Jid bare_jid = new Jid(bot.jid);

            // Build minimal module set for bot operation
            var modules = new ArrayList<XmppStreamModule>();
            modules.add(new Iq.Module());
            modules.add(new Sasl.Module(bare_jid.to_string(), bot.bot_password));
            modules.add(new Xep.StreamManagement.Module());
            modules.add(new Bind.Module("bot"));
            modules.add(new Session.Module());
            // ServiceDiscovery MUST come before modules that call add_feature()
            modules.add(new Xep.ServiceDiscovery.Module.with_identity("client", "bot", "DinoX Bot"));
            modules.add(new Presence.Module());
            modules.add(new Xmpp.MessageModule());
            modules.add(new Xep.Ping.Module());
            modules.add(new StreamError.Module());
            modules.add(new Xep.DelayedDelivery.Module());
            modules.add(new Roster.Module());
            modules.add(new Xep.VCard.Module());

            // OMEMO: add PubSub + StreamModule for E2E encryption
            modules.add(new Xep.Pubsub.Module());
            if (bot_omemo != null) {
                bot_omemo.init_bot(bot.id);
                var omemo_module = bot_omemo.create_stream_module(bot.id);
                if (omemo_module != null) {
                    modules.add(omemo_module);
                    message("SessionPool: Added OMEMO module for bot %d (device_id=%u)",
                        bot.id, bot_omemo.get_device_id(bot.id));
                }
            }

            message("SessionPool: Connecting dedicated bot %d as %s ...", bot.id, bot.jid);

            XmppStreamResult result = yield Xmpp.establish_stream(
                bare_jid, modules, null,
                (peer_cert, errors) => { return true; }  // accept self-signed certs
            );

            if (result.stream != null) {
                int bot_id = bot.id;
                bot_infos[bot_id] = bot;

                // Set up callbacks BEFORE loop() starts processing
                // stream_negotiated fires when SASL+Bind are done
                result.stream.stream_negotiated.connect((stream) => {
                    on_bot_stream_ready(bot_id, stream);
                });

                // Listen for incoming messages
                result.stream.get_module<Xmpp.MessageModule>(Xmpp.MessageModule.IDENTITY)
                    .received_message.connect((stream, msg_stanza) => {
                        on_dedicated_message(bot_id, msg_stanza);
                    });

                // Only accept subscriptions from the bot's owner
                string? owner_jid_str = bot.owner_jid;
                result.stream.get_module<Presence.Module>(Presence.Module.IDENTITY)
                    .received_subscription_request.connect((stream, jid) => {
                        if (owner_jid_str != null && jid.bare_jid.to_string() == owner_jid_str) {
                            message("SessionPool: Bot %d approving subscription from owner %s", bot_id, jid.to_string());
                            stream.get_module<Presence.Module>(Presence.Module.IDENTITY)
                                .approve_subscription(stream, jid.bare_jid);
                            stream.get_module<Presence.Module>(Presence.Module.IDENTITY)
                                .request_subscription(stream, jid.bare_jid);
                        } else {
                            warning("SessionPool: Bot %d REJECTED subscription from non-owner %s (owner=%s)",
                                bot_id, jid.to_string(), owner_jid_str ?? "(null)");
                        }
                    });

                // Store stream now so it's available when negotiation completes
                dedicated_streams[bot_id] = result.stream;

                // Wire OMEMO signal handlers (bundle auto-session, device list cache)
                if (bot_omemo != null) {
                    bot_omemo.wire_signals(bot_id, result.stream);
                }

                message("SessionPool: Bot %d stream created, starting negotiation...", bot.id);

                // Run the stream event loop (handles SASL, Bind, then keeps alive)
                run_stream_loop.begin(bot.id, result.stream);

                connecting[bot.id] = false;
                return true;
            } else {
                string err = "unknown";
                if (result.io_error != null) err = result.io_error.message;
                warning("SessionPool: Failed to connect bot %d: %s", bot.id, err);
                connecting[bot.id] = false;
                return false;
            }
        } catch (Error e) {
            warning("SessionPool: Error connecting bot %d: %s", bot.id, e.message);
            connecting[bot.id] = false;
            return false;
        }
    }

    // Called when SASL + Bind negotiation is complete
    private void on_bot_stream_ready(int bot_id, XmppStream stream) {
        message("SessionPool: Bot %d fully negotiated and ready!", bot_id);
        on_bot_stream_ready_async.begin(bot_id, stream);
    }

    private async void on_bot_stream_ready_async(int bot_id, XmppStream stream) {
        // Send initial presence (online)
        stream.get_module<Presence.Module>(Presence.Module.IDENTITY)
            .send_presence(stream, new Presence.Stanza());

        // All publishes sequential to avoid overloading ejabberd c2s shaper
        BotInfo? bot = bot_infos.has_key(bot_id) ? bot_infos[bot_id] : null;

        // 1. Publish vCard with bot name (wait for completion)
        if (bot != null && bot.name != null) {
            yield publish_bot_vcard(bot_id, stream, bot.name);
        }

        // 2. Publish OMEMO device list + bundle (sequential)
        // MUST complete BEFORE we fire dedicated_bot_ready (which sets encryption)
        if (bot_omemo != null && bot_omemo.is_initialized(bot_id)) {
            yield publish_bot_omemo(bot_id, stream);
        }

        // 3. Notify listeners (plugin.vala) to set roster handle + OMEMO encryption
        if (bot != null) {
            dedicated_bot_ready(bot_id, bot);
        }
    }

    /**
     * Publish the bot's OMEMO device list and bundle via PubSub.
     * Sequential to respect ejabberd c2s shaper rate limits.
     * Make-public runs fire-and-forget since it's not on the critical path.
     */
    private async void publish_bot_omemo(int bot_id, XmppStream stream) {
        uint32 device_id = bot_omemo.get_device_id(bot_id);
        if (device_id == 0) return;

        Jid? my_jid = stream.get_flag(Bind.Flag.IDENTITY) != null
            ? stream.get_flag(Bind.Flag.IDENTITY).my_jid : null;
        if (my_jid == null) {
            warning("SessionPool: Bot %d has no bound JID yet", bot_id);
            return;
        }

        message("SessionPool: Publishing OMEMO for bot %d (device_id=%u, jid=%s)",
            bot_id, device_id, my_jid.to_string());

        // 1. Device list first (small payload)
        yield publish_device_list(bot_id, stream, device_id);

        // 2. Then bundle (bigger payload with 100 pre-keys)
        yield bot_omemo.publish_bundle(bot_id, stream);

        message("SessionPool: Bot %d OMEMO publish complete", bot_id);
    }

    /** Publish device list and make node public (background-safe). */
    private async void publish_device_list(int bot_id, XmppStream stream, uint32 device_id) {
        var list_node = new StanzaNode.build("list", "eu.siacs.conversations.axolotl")
            .add_self_xmlns();
        var device_node = new StanzaNode.build("device", "eu.siacs.conversations.axolotl")
            .put_attribute("id", device_id.to_string());
        list_node.put_node(device_node);

        yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
            .publish(stream, null, "eu.siacs.conversations.axolotl.devicelist",
                     "current", list_node);
        message("SessionPool: Bot %d device list published", bot_id);

        // Make device list node publicly accessible (fire-and-forget)
        try_make_pubsub_node_public.begin(stream, "eu.siacs.conversations.axolotl.devicelist");
    }

    /** Make a PubSub node publicly accessible so other clients can read it. */
    private async void try_make_pubsub_node_public(XmppStream stream, string node_id) {
        Xep.DataForms.DataForm? form = yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
            .request_node_config(stream, null, node_id);
        if (form == null) return;
        foreach (Xep.DataForms.DataForm.Field field in form.fields) {
            if (field.var == "pubsub#access_model" && field.get_value_string() != Xep.Pubsub.ACCESS_MODEL_OPEN) {
                field.set_value_string(Xep.Pubsub.ACCESS_MODEL_OPEN);
                yield stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY)
                    .submit_node_config(stream, null, form, node_id);
                message("SessionPool: Made node %s public", node_id);
                break;
            }
        }
    }

    // Publish a vCard with the bot's display name and avatar
    private async void publish_bot_vcard(int bot_id, XmppStream stream, string bot_name) {
        try {
            var vcard = new Xep.VCard.VCardInfo();
            vcard.full_name = bot_name;
            vcard.nickname = bot_name;

            // Load avatar from settings if available
            if (registry != null) {
                string? avatar_b64 = registry.get_setting("bot_avatar:%d".printf(bot_id));
                string? avatar_type = registry.get_setting("bot_avatar_type:%d".printf(bot_id));
                if (avatar_b64 != null && avatar_b64.length > 0) {
                    vcard.photo = new GLib.Bytes(GLib.Base64.decode(avatar_b64));
                    vcard.photo_type = avatar_type ?? "image/png";
                    message("SessionPool: Publishing vCard with avatar for bot %d", bot_id);
                }
            }

            yield Xep.VCard.publish_vcard(stream, vcard);
            message("SessionPool: Published vCard for bot %d: %s", bot_id, bot_name);
        } catch (Error e) {
            warning("SessionPool: Failed to publish vCard for bot %d: %s", bot_id, e.message);
        }
    }

    // Run the stream loop to keep the connection alive and process stanzas
    private async void run_stream_loop(int bot_id, TlsXmppStream stream) {
        try {
            yield stream.loop();
        } catch (Error e) {
            warning("SessionPool: Bot %d stream error: %s", bot_id, e.message);
        }
        // Stream disconnected
        dedicated_streams.unset(bot_id);
        connecting[bot_id] = false;
        message("SessionPool: Bot %d disconnected, will reconnect on next use", bot_id);
    }

    // Handle incoming messages on a dedicated bot stream
    private void on_dedicated_message(int bot_id, Xmpp.MessageStanza msg) {
        // Only accept messages from the bot's owner
        if (msg.from != null) {
            BotInfo? bot = bot_infos.has_key(bot_id) ? bot_infos[bot_id] : null;
            if (bot != null && bot.owner_jid != null) {
                string sender = msg.from.bare_jid.to_string();
                if (sender != bot.owner_jid) {
                    warning("SessionPool: Bot %d IGNORED message from non-owner %s (owner=%s)",
                        bot_id, sender, bot.owner_jid);
                    return;
                }
            }
        }

        // Try OMEMO decryption first
        if (bot_omemo != null && bot_omemo.is_omemo_encrypted(msg)) {
            string? plaintext = bot_omemo.decrypt_message(bot_id, msg);
            if (plaintext != null) {
                msg.body = plaintext;
                message("SessionPool: Decrypted OMEMO message for bot %d", bot_id);
            } else {
                warning("SessionPool: OMEMO decryption failed for bot %d", bot_id);
                return; // drop undecryptable OMEMO messages
            }
        }

        if (msg.body == null || msg.body.strip() == "") return;
        // Emit signal so MessageRouter can handle it
        dedicated_message_received(bot_id, msg);
    }

    // Send a message from a dedicated bot to a JID (tries OMEMO first)
    public bool send_message_for_bot(int bot_id, string to_jid, string body) {
        if (!dedicated_streams.has_key(bot_id)) return false;
        var stream = dedicated_streams[bot_id];

        // Try OMEMO-encrypted send
        if (bot_omemo != null && bot_omemo.is_initialized(bot_id)) {
            try {
                Jid jid = new Jid(to_jid);
                bot_omemo.encrypt_and_send.begin(bot_id, stream, jid, body, (obj, res) => {
                    bool ok = bot_omemo.encrypt_and_send.end(res);
                    if (!ok) {
                        // Fallback: send plaintext
                        warning("SessionPool: OMEMO send failed for bot %d, falling back to plaintext", bot_id);
                        send_plaintext(bot_id, stream, to_jid, body);
                    }
                });
                return true;
            } catch (Error e) {
                warning("SessionPool: OMEMO send error for bot %d: %s", bot_id, e.message);
            }
        }

        // Fallback: plaintext
        return send_plaintext(bot_id, stream, to_jid, body);
    }

    private bool send_plaintext(int bot_id, XmppStream stream, string to_jid, string body) {
        try {
            var msg_stanza = new Xmpp.MessageStanza();
            msg_stanza.to = new Jid(to_jid);
            msg_stanza.type_ = Xmpp.MessageStanza.TYPE_CHAT;
            msg_stanza.body = body;
            stream.get_module<Xmpp.MessageModule>(Xmpp.MessageModule.IDENTITY)
                .send_message.begin(stream, msg_stanza);
            return true;
        } catch (Error e) {
            warning("SessionPool: Failed to send message for bot %d: %s", bot_id, e.message);
            return false;
        }
    }

    /**
     * Clean up PubSub nodes for a bot before disconnecting.
     * Must be called while the stream is still alive.
     */
    public void cleanup_pubsub_and_disconnect(int bot_id, uint32 device_id) {
        if (!dedicated_streams.has_key(bot_id)) return;
        var stream = dedicated_streams[bot_id];

        // Delete OMEMO PubSub nodes (device list + bundle)
        var pubsub = stream.get_module<Xep.Pubsub.Module>(Xep.Pubsub.Module.IDENTITY);
        pubsub.delete_node(stream, null, "eu.siacs.conversations.axolotl.devicelist");
        message("SessionPool: Deleted device list node for bot %d", bot_id);

        if (device_id > 0) {
            string bundle_node = "eu.siacs.conversations.axolotl.bundles:%u".printf(device_id);
            pubsub.delete_node(stream, null, bundle_node);
            message("SessionPool: Deleted bundle node %s for bot %d", bundle_node, bot_id);
        }

        // Delete avatar node
        pubsub.delete_node(stream, null, "urn:xmpp:avatar:data");
        pubsub.delete_node(stream, null, "urn:xmpp:avatar:metadata");

        // Delete vCard node
        pubsub.delete_node(stream, null, "urn:xmpp:vcard4");

        // Give the delete IQs a moment to send, then disconnect
        GLib.Timeout.add(500, () => {
            disconnect_dedicated(bot_id);
            return false;
        });
    }

    // Disconnect a specific dedicated bot
    public void disconnect_dedicated(int bot_id) {
        if (dedicated_streams.has_key(bot_id)) {
            dedicated_streams[bot_id].disconnect.begin();
            dedicated_streams.unset(bot_id);
            connecting[bot_id] = false;
            message("SessionPool: Disconnected dedicated bot %d", bot_id);
        }
    }

    // Connect all active dedicated bots
    public void connect_all_dedicated() {
        if (registry == null) return;
        var bots = registry.get_all_active_bots();
        foreach (BotInfo bot in bots) {
            if (bot.mode == "dedicated" && bot.jid != null && bot.bot_password != null) {
                connect_dedicated.begin(bot);
            }
        }
    }

    private Account? get_first_active_account() {
        foreach (Account account in app.stream_interactor.get_accounts()) {
            if (app.stream_interactor.get_stream(account) != null) {
                return account;
            }
        }
        return null;
    }

    public void disconnect_all() {
        personal_bindings.clear();
        // Disconnect all dedicated streams
        foreach (var entry in dedicated_streams.entries) {
            entry.value.disconnect.begin();
        }
        dedicated_streams.clear();
        connecting.clear();
    }
}

}
