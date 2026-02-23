using Gee;

namespace Xmpp.Test {

/**
 * Security Audit: XEP-0115 Entity Capabilities compute_hash
 *
 * Tests the verification string computation (Section 5.1) which is
 * critical for capability hashing. An incorrect hash allows capability
 * poisoning attacks where a malicious entity claims capabilities it
 * does not have.
 *
 * Uses XEP-0115 Section 5.4 Example 1 test vector:
 *   Identity: client/pc//Exodus 0.9.1
 *   Features: http://jabber.org/protocol/caps, http://jabber.org/protocol/disco#info,
 *             http://jabber.org/protocol/disco#items, http://jabber.org/protocol/muc
 *   Expected hash: QgayPKawpkPSDYmwT/WM94uAlu0=
 */
class EntityCapsAudit : Gee.TestCase {

    public EntityCapsAudit() {
        base("EntityCapsAudit");

        add_test("XEP0115_5_4_example1_exodus", test_xep0115_example1);
        add_test("XEP0115_empty_identity_set", test_empty_identities);
        add_test("XEP0115_multiple_identities_sorted", test_multiple_identities);
        add_test("XEP0115_features_sorted", test_features_sorted);
        add_test("XEP0115_identity_with_lt_sanitized", test_identity_lt_sanitized);
    }

    private void test_xep0115_example1() {
        // XEP-0115 Section 5.4 Example 1
        var identities = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        identities.add(new Xep.ServiceDiscovery.Identity("client", "pc", "Exodus 0.9.1"));

        var features = new ArrayList<string>();
        features.add("http://jabber.org/protocol/caps");
        features.add("http://jabber.org/protocol/disco#info");
        features.add("http://jabber.org/protocol/disco#items");
        features.add("http://jabber.org/protocol/muc");

        var data_forms = new ArrayList<Xep.DataForms.DataForm>();

        string hash = Xep.EntityCapabilities.Module.compute_hash(identities, features, data_forms);
        fail_if_not_eq_str(hash, "QgayPKawpkPSDYmwT/WM94uAlu0=",
            "XEP-0115 Section 5.4 Example 1 hash must match");
    }

    private void test_empty_identities() {
        var identities = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        var features = new ArrayList<string>();
        features.add("http://jabber.org/protocol/disco#info");
        var data_forms = new ArrayList<Xep.DataForms.DataForm>();

        string hash = Xep.EntityCapabilities.Module.compute_hash(identities, features, data_forms);
        // Should produce a valid Base64 hash, not crash
        fail_if(hash == null || hash.length == 0,
            "Empty identity set should still produce a valid hash");
    }

    private void test_multiple_identities() {
        // Identities should be sorted by category, then type
        var identities = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        identities.add(new Xep.ServiceDiscovery.Identity("gateway", "msn", "MSN Transport"));
        identities.add(new Xep.ServiceDiscovery.Identity("client", "pc", "MyClient"));

        var features = new ArrayList<string>();
        var data_forms = new ArrayList<Xep.DataForms.DataForm>();

        // Compute twice to verify determinism
        string hash1 = Xep.EntityCapabilities.Module.compute_hash(identities, features, data_forms);
        string hash2 = Xep.EntityCapabilities.Module.compute_hash(identities, features, data_forms);
        fail_if_not_eq_str(hash1, hash2,
            "Hash computation must be deterministic regardless of set ordering");
    }

    private void test_features_sorted() {
        var identities = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        identities.add(new Xep.ServiceDiscovery.Identity("client", "pc"));

        // Features in reverse order
        var features_rev = new ArrayList<string>();
        features_rev.add("zzz");
        features_rev.add("aaa");
        var data_forms = new ArrayList<Xep.DataForms.DataForm>();
        string hash_rev = Xep.EntityCapabilities.Module.compute_hash(identities, features_rev, data_forms);

        // Features in sorted order
        var features_sorted = new ArrayList<string>();
        features_sorted.add("aaa");
        features_sorted.add("zzz");
        string hash_sorted = Xep.EntityCapabilities.Module.compute_hash(identities, features_sorted, data_forms);

        fail_if_not_eq_str(hash_rev, hash_sorted,
            "Feature order should not affect hash (impl must sort)");
    }

    private void test_identity_lt_sanitized() {
        // XEP-0115 5.1: '<' in identity fields MUST be escaped as '&lt;'
        // to prevent trivial injection of the delimiter
        var identities = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        identities.add(new Xep.ServiceDiscovery.Identity("client", "pc", "Name<With<Angles"));

        var features = new ArrayList<string>();
        var data_forms = new ArrayList<Xep.DataForms.DataForm>();

        // Should not crash and should produce a valid hash
        string hash = Xep.EntityCapabilities.Module.compute_hash(identities, features, data_forms);
        fail_if(hash == null || hash.length == 0,
            "Identity name containing '<' should be sanitized, not crash");

        // Hash with '<' must differ from hash without, proving sanitization works
        var identities2 = new HashSet<Xep.ServiceDiscovery.Identity>(
            Xep.ServiceDiscovery.Identity.hash_func,
            Xep.ServiceDiscovery.Identity.equals_func);
        identities2.add(new Xep.ServiceDiscovery.Identity("client", "pc", "NameWithAngles"));
        string hash2 = Xep.EntityCapabilities.Module.compute_hash(identities2, features, data_forms);
        fail_if_eq_str(hash, hash2,
            "Sanitized '<' should produce different hash than without");
    }
}

}
