using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino {

public class UserSearch : Object {
    private StreamInteractor stream_interactor;

    public UserSearch(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public async Jid? find_search_component(Account account) {
        var stream = stream_interactor.get_stream(account);
        if (stream == null) return null;

        var disco_module = stream.get_module<Xmpp.Xep.ServiceDiscovery.Module>(Xmpp.Xep.ServiceDiscovery.Module.IDENTITY);
        
        // 0. Check server features first
        try {
            debug("Requesting disco info from %s", account.domainpart);
            var info = yield disco_module.request_info(stream, new Jid(account.domainpart));
            if (info != null) {
                debug("Server features: %s", string.joinv(", ", info.features.to_array()));
                if (info.features.contains(Xmpp.Xep.Search.NS_URI)) {
                    debug("Server %s supports search directly", account.domainpart);
                    return new Jid(account.domainpart);
                }
            }
        } catch (Error e) {
            debug("Error checking server info: %s", e.message);
        }

        // 1. Check server items
        try {
            debug("Requesting disco items from %s", account.domainpart);
            var items = yield disco_module.request_items(stream, new Jid(account.domainpart));
            if (items == null) {
                debug("No items returned from %s", account.domainpart);
                return null;
            }

            foreach (var item in items.items) {
                debug("Checking item %s", item.jid.to_string());
                // 2. Check features of each item
                var info = yield disco_module.request_info(stream, item.jid);
                if (info != null) {
                    if (info.features.contains(Xmpp.Xep.Search.NS_URI)) {
                        debug("Found search component: %s", item.jid.to_string());
                        return item.jid;
                    } else {
                        debug("Item %s does not have search feature", item.jid.to_string());
                    }
                } else {
                    debug("Could not get info for item %s", item.jid.to_string());
                }
            }
        } catch (Error e) {
            warning("Error finding search component: %s", e.message);
        }
        
        return null;
    }

    public async Xmpp.Xep.DataForms.DataForm? get_search_fields(Account account, Jid search_jid) {
        var stream = stream_interactor.get_stream(account);
        if (stream == null) return null;
        var search_module = stream.get_module<Xmpp.Xep.Search.Module>(Xmpp.Xep.Search.Module.IDENTITY);
        try {
            return yield search_module.get_fields(stream, search_jid);
        } catch (Error e) {
            warning("Error getting search fields: %s", e.message);
            return null;
        }
    }

    public async Gee.List<Xmpp.Xep.Search.Item>? perform_search(Account account, Jid search_jid, Xmpp.Xep.DataForms.DataForm form, bool legacy_only = false) {
        var stream = stream_interactor.get_stream(account);
        if (stream == null) return null;
        var search_module = stream.get_module<Xmpp.Xep.Search.Module>(Xmpp.Xep.Search.Module.IDENTITY);
        try {
            return yield search_module.search(stream, search_jid, form, legacy_only);
        } catch (Error e) {
            warning("Error performing search: %s", e.message);
            return null;
        }
    }
}

}
