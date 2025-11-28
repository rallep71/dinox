/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gee;

using Dino.Entities;
using Xmpp;

namespace Dino {
    public static string get_conversation_display_name(StreamInteractor stream_interactor, Conversation conversation, string? muc_pm_format) {
        if (conversation.type_ == Conversation.Type.CHAT) {
            string? display_name = get_real_display_name(stream_interactor, conversation.account, conversation.counterpart);
            if (display_name != null) return display_name;
            return conversation.counterpart.to_string();
        }
        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            return get_groupchat_display_name(stream_interactor, conversation.account, conversation.counterpart);
        }
        if (conversation.type_ == Conversation.Type.GROUPCHAT_PM) {
            return (muc_pm_format ?? "%s / %s").printf(get_occupant_display_name(stream_interactor, conversation, conversation.counterpart), get_groupchat_display_name(stream_interactor, conversation.account, conversation.counterpart.bare_jid));
        }
        return conversation.counterpart.to_string();
    }

    public static string get_participant_display_name(StreamInteractor stream_interactor, Conversation conversation, Jid participant, string? self_word = null) {
        if (conversation.type_ == Conversation.Type.CHAT) {
            return get_real_display_name(stream_interactor, conversation.account, participant, self_word) ?? participant.bare_jid.to_string();
        }
        if ((conversation.type_ == Conversation.Type.GROUPCHAT || conversation.type_ == Conversation.Type.GROUPCHAT_PM)) {
            return get_occupant_display_name(stream_interactor, conversation, participant);
        }
        return participant.bare_jid.to_string();
    }

    public static string? get_real_display_name(StreamInteractor stream_interactor, Account account, Jid jid, string? self_word = null) {
        if (jid.equals_bare(account.bare_jid)) {
            if (self_word != null && (account.alias == null || account.alias.length == 0)) {
                return self_word;
            }
            if (account.alias != null && account.alias.length == 0) return null;
            return account.alias;
        }
        Roster.Item roster_item = stream_interactor.get_module(RosterManager.IDENTITY).get_roster_item(account, jid);
        if (roster_item != null && roster_item.name != null && roster_item.name != "") {
            return roster_item.name;
        }
        return null;
    }

    public static string get_groupchat_display_name(StreamInteractor stream_interactor, Account account, Jid jid) {
        MucManager muc_manager = stream_interactor.get_module(MucManager.IDENTITY);
        
        // Priority 1: User's personal bookmark name (highest priority)
        string? bookmark_name = muc_manager.get_bookmark_name(account, jid);
        if (bookmark_name != null && bookmark_name.strip() != "") {
            debug("get_groupchat_display_name: Using bookmark_name '%s' for %s", bookmark_name, jid.to_string());
            return bookmark_name;
        }
        
        // Priority 2: Use JID localpart (the actual MUC address name)
        // We deliberately skip room_name from server config because:
        // - If user clears their bookmark name, they want to see the JID name
        // - room_name from server config may be outdated or confusing
        debug("get_groupchat_display_name: Using localpart '%s' for %s (no bookmark)", jid.localpart ?? "(null)", jid.to_string());
        if (jid.localpart != null) {
            return jid.localpart;
        }
        
        return jid.to_string();
    }

    public static string get_occupant_display_name(StreamInteractor stream_interactor, Conversation conversation, Jid jid, string? self_word = null, bool muc_real_name = false) {
        if (muc_real_name) {
            MucManager muc_manager = stream_interactor.get_module(MucManager.IDENTITY);
            if (muc_manager.is_private_room(conversation.account, conversation.counterpart)) {
                Jid? real_jid = null;
                if (jid.equals_bare(conversation.counterpart)) {
                    muc_manager.get_real_jid(jid, conversation.account);
                } else {
                    real_jid = jid;
                }
                if (real_jid != null) {
                    string? display_name = get_real_display_name(stream_interactor, conversation.account, real_jid, self_word);
                    if (display_name != null) return display_name;
                }
            }
        }

        // If it's us (jid=our real full JID), display our nick
        if (conversation.type_ == Conversation.Type.GROUPCHAT_PM && conversation.account.bare_jid.equals_bare(jid)) {
            var muc_conv = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation(conversation.counterpart.bare_jid, conversation.account, Conversation.Type.GROUPCHAT);
            if (muc_conv != null && muc_conv.nickname != null) {
                return muc_conv.nickname;
            }
        }

        // If it's someone else's real jid, recover nickname
        if (!jid.equals_bare(conversation.counterpart)) {
            MucManager muc_manager = stream_interactor.get_module(MucManager.IDENTITY);
            Jid? occupant_jid = muc_manager.get_occupant_jid(conversation.account, conversation.counterpart.bare_jid, jid);
            if (occupant_jid != null && occupant_jid.resourcepart != null) {
                return occupant_jid.resourcepart;
            }
        }

        return jid.resourcepart ?? jid.to_string();
    }
}
