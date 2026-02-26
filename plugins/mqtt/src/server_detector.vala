/*
 * ServerDetector — Detect MQTT capabilities of the XMPP server.
 *
 * Uses XEP-0030 Service Discovery (disco#info + disco#items) to determine
 * whether the XMPP server offers MQTT connectivity:
 *
 *   - ejabberd (mod_mqtt):  Server lists "urn:xmpp:mqtt:0" or an item
 *                           with identity type "mqtt" in disco#items.
 *                           In practice, ejabberd exposes mod_mqtt as a
 *                           separate listener (not advertised via disco).
 *                           We fall back to probing the MQTT port.
 *
 *   - Prosody (mod_pubsub_mqtt):  A PubSub component may list MQTT in its
 *                                  features.  We look for pubsub items with
 *                                  the "pubsub" identity.
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Dino.Entities;
using Gee;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Plugins.Mqtt {

/**
 * Detected MQTT server type.
 */
public enum ServerType {
    UNKNOWN,
    EJABBERD,      /* ejabberd with mod_mqtt */
    PROSODY,       /* Prosody with mod_pubsub_mqtt */
    STANDALONE;    /* External / generic broker */

    public string to_label() {
        switch (this) {
            case EJABBERD:   return "ejabberd (mod_mqtt)";
            case PROSODY:    return "Prosody (mod_pubsub_mqtt)";
            case STANDALONE: return "Standalone Broker";
            default:         return "Unknown";
        }
    }

    public string to_string_key() {
        switch (this) {
            case EJABBERD:   return "ejabberd";
            case PROSODY:    return "prosody";
            case STANDALONE: return "standalone";
            default:         return "unknown";
        }
    }

    public static ServerType from_string(string s) {
        switch (s) {
            case "ejabberd":   return EJABBERD;
            case "prosody":    return PROSODY;
            case "standalone": return STANDALONE;
            default:           return UNKNOWN;
        }
    }
}

/**
 * Result of a server detection.
 */
public class DetectionResult {
    public ServerType server_type { get; set; default = ServerType.UNKNOWN; }
    public bool has_pubsub { get; set; default = false; }
    public string? pubsub_jid { get; set; default = null; }
    public string info { get; set; default = ""; }

    public DetectionResult() {}
}

/**
 * Detect MQTT capabilities via XEP-0030. Stateless — just call detect().
 */
public class ServerDetector {

    /**
     * Run detection for the given account's XMPP server.
     * Returns a DetectionResult.
     */
    public static async DetectionResult detect(StreamInteractor stream_interactor,
                                               Account account) {
        var result = new DetectionResult();
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) {
            result.info = "No XMPP stream available";
            return result;
        }

        var disco = stream.get_module<ServiceDiscovery.Module>(
            ServiceDiscovery.Module.IDENTITY);
        if (disco == null) {
            result.info = "Service Discovery module not available";
            return result;
        }

        Jid server_jid = account.bare_jid.domain_jid;

        /* Step 1: Query server identity */
        ServiceDiscovery.InfoResult? server_info =
            yield disco.request_info(stream, server_jid);

        if (server_info != null) {
            /* Check identities for server type hints */
            foreach (var identity in server_info.identities) {
                string cat = identity.category ?? "";
                string typ = identity.type_ ?? "";
                string nam = (identity.name ?? "").down();

                if (nam.contains("ejabberd")) {
                    result.server_type = ServerType.EJABBERD;
                    result.info = "Detected ejabberd via server identity";
                    message("MQTT ServerDetector: ejabberd detected (identity: %s/%s '%s')",
                            cat, typ, identity.name ?? "");
                } else if (nam.contains("prosody")) {
                    result.server_type = ServerType.PROSODY;
                    result.info = "Detected Prosody via server identity";
                    message("MQTT ServerDetector: Prosody detected (identity: %s/%s '%s')",
                            cat, typ, identity.name ?? "");
                }
            }
        }

        /* Step 2: Enumerate disco#items for PubSub / MQTT components */
        ServiceDiscovery.ItemsResult? items =
            yield disco.request_items(stream, server_jid);
        if (items != null) {
            foreach (var item in items.items) {
                ServiceDiscovery.InfoResult? item_info =
                    yield disco.request_info(stream, item.jid);
                if (item_info == null) continue;

                foreach (var id in item_info.identities) {
                    if (id.category == "pubsub") {
                        result.has_pubsub = true;
                        result.pubsub_jid = item.jid.to_string();
                        message("MQTT ServerDetector: PubSub component found at %s",
                                item.jid.to_string());
                    }
                }

                /* Check features for MQTT-related namespaces */
                foreach (string feature in item_info.features) {
                    if (feature.contains("mqtt")) {
                        message("MQTT ServerDetector: MQTT feature found: %s at %s",
                                feature, item.jid.to_string());
                        if (result.server_type == ServerType.UNKNOWN) {
                            result.server_type = ServerType.EJABBERD;
                            result.info = "MQTT feature discovered: " + feature;
                        }
                    }
                }
            }
        }

        /* Step 3: If Prosody detected + PubSub found, assume mod_pubsub_mqtt */
        if (result.server_type == ServerType.PROSODY && result.has_pubsub) {
            result.info = "Prosody with PubSub (likely mod_pubsub_mqtt)";
        }

        if (result.server_type == ServerType.UNKNOWN) {
            result.info = "No MQTT server type detected — configure manually";
        }

        message("MQTT ServerDetector: Result = %s (%s)",
                result.server_type.to_label(), result.info);
        return result;
    }
}

}
