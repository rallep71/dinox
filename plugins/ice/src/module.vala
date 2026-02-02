using Gee;
using Xmpp;
using Xmpp.Xep;

public class Dino.Plugins.Ice.Module : JingleIceUdp.Module {

    public string? stun_ip = null;
    public uint stun_port = 0;
    public string? turn_ip = null;
    public Xep.ExternalServiceDiscovery.Service? turn_service = null;

    private HashMap<string, DtlsSrtp.CredentialsCapsule> cerds = new HashMap<string, DtlsSrtp.CredentialsCapsule>();

    // Create a fresh agent for each call - this ensures clean TURN allocations
    private Nice.Agent create_agent() {
        Nice.Agent agent = new Nice.Agent(MainContext.@default(), Nice.Compatibility.RFC5245);
        if (stun_ip != null) {
            agent.stun_server = stun_ip;
            agent.stun_server_port = stun_port;
        }
        agent.set_software("Dino");
        
        // Standard ICE settings
        agent.upnp = false;                   // Disable UPnP to avoid timeouts/delays
        agent.stun_max_retransmissions = 7;   // Default is usually sufficient
        agent.stun_initial_timeout = 500;     // Default 500ms
        agent.keepalive_conncheck = true;
        agent.ice_trickle = true;
        agent.ice_tcp = true;                 // Enable ICE-TCP for better stability
        
        debug("Created new Nice.Agent with STUN server %s:%u", agent.stun_server ?? "(none)", agent.stun_server_port);
        return agent;
    }

    public override Jingle.TransportParameters create_transport_parameters(XmppStream stream, uint8 components, Jid local_full_jid, Jid peer_full_jid) {
        DtlsSrtp.CredentialsCapsule? cred = get_create_credentials(local_full_jid, peer_full_jid);
        return new TransportParameters(create_agent(), cred, turn_service, turn_ip, components, local_full_jid, peer_full_jid);
    }

    public override Jingle.TransportParameters parse_transport_parameters(XmppStream stream, uint8 components, Jid local_full_jid, Jid peer_full_jid, StanzaNode transport) throws Jingle.IqError {
        DtlsSrtp.CredentialsCapsule? cred = get_create_credentials(local_full_jid, peer_full_jid);
        return new TransportParameters(create_agent(), cred, turn_service, turn_ip, components, local_full_jid, peer_full_jid, transport);
    }

    private DtlsSrtp.CredentialsCapsule? get_create_credentials(Jid local_full_jid, Jid peer_full_jid) {
        string from_to_id = local_full_jid.to_string() + peer_full_jid.to_string();
        try {
            if (!cerds.has_key(from_to_id)) cerds[from_to_id] = DtlsSrtp.Handler.generate_credentials();
        } catch (Error e) {
            warning("Error creating dtls credentials: %s", e.message);
        }
        return cerds[from_to_id];
    }
}
