/**
 * Security audit tests for OMEMO v1/v2 session version guard.
 *
 * XEP-0384: OmemoEncryptor.encrypt_key() has a guard:
 *   if (cipher.get_session_version() >= 4) → reject session, throw error
 *
 * This prevents v4 (OMEMO 2) sessions from being used in the v1 encryptor,
 * which would produce messages the recipient would try to decrypt
 * as OMEMO v2 format (AES-CBC + HMAC) instead of v1 (AES-GCM).
 *
 * These tests verify session version detection works correctly using
 * the Signal protocol store infrastructure.
 */

namespace Omemo.Test {

class SessionVersionGuardTest : Gee.TestCase {

    private Context global_context;
    private Address alice_address;
    private Address bob_address;

    public SessionVersionGuardTest() {
        base("SessionVersionGuard");

        add_test("XEP0384_v3_session_reports_version_3", test_v3_session_version);
        add_test("XEP0384_session_cipher_version_matches_record", test_cipher_matches_record);
        add_test("XEP0384_no_session_version_zero", test_no_session_version);
    }

    public override void set_up() {
        try {
            global_context = new Context();
            alice_address = new Address("+14151111111", 1);
            bob_address = new Address("+14152222222", 1);
        } catch (Error e) {
            fail_if_reached(@"setup failed: $(e.message)");
        }
    }

    public override void tear_down() {
        global_context = null;
        alice_address = null;
        bob_address = null;
    }

    /**
     * XEP-0384: v3 session (OMEMO v1) must report session_version == 3.
     *
     * The encrypt_key guard rejects sessions with version >= 4.
     * All sessions built from v3 pre-key bundles must report version 3
     * so the guard does NOT fire for legitimate OMEMO v1 sessions.
     */
    private void test_v3_session_version() {
        try {
            Store alice_store = setup_test_store_context(global_context);
            SessionBuilder alice_session_builder = alice_store.create_session_builder(bob_address);

            Store bob_store = setup_test_store_context(global_context);
            uint32 bob_reg_id = bob_store.local_registration_id;
            ECKeyPair bob_pre_key = global_context.generate_key_pair();
            ECKeyPair bob_signed_pre_key = global_context.generate_key_pair();
            IdentityKeyPair bob_identity = bob_store.identity_key_pair;

            uint8[] sig = global_context.calculate_signature(
                bob_identity.private, bob_signed_pre_key.public.serialize());

            PreKeyBundle bundle = create_pre_key_bundle(
                bob_reg_id, 1, 31337, bob_pre_key.public,
                22, bob_signed_pre_key.public, sig, bob_identity.public);

            alice_session_builder.process_pre_key_bundle(bundle);

            /* Verify session version via SessionRecord */
            SessionRecord record = alice_store.load_session(bob_address);
            fail_if_not_eq_int((int)record.state.session_version, 3,
                "XEP-0384: v3 session must report version 3 (guard threshold is >= 4)");

            /* Verify session version via SessionCipher */
            SessionCipher cipher = alice_store.create_session_cipher(bob_address);
            uint32 ver = cipher.get_session_version();
            fail_if_not_eq_int((int)ver, 3,
                "XEP-0384: cipher.get_session_version() must return 3 for v3 session");

            /* This is the guard condition from encrypt_key: must NOT trigger */
            fail_if(ver >= 4,
                "XEP-0384: v3 session must NOT trigger version >= 4 guard");

        } catch (Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384: SessionCipher version must match SessionRecord version.
     *
     * If these ever disagree, the version guard in encrypt_key could
     * make wrong decisions.
     */
    private void test_cipher_matches_record() {
        try {
            Store alice_store = setup_test_store_context(global_context);
            SessionBuilder builder = alice_store.create_session_builder(bob_address);

            Store bob_store = setup_test_store_context(global_context);
            ECKeyPair bob_pre_key = global_context.generate_key_pair();
            ECKeyPair bob_signed_pre_key = global_context.generate_key_pair();
            IdentityKeyPair bob_identity = bob_store.identity_key_pair;
            uint8[] sig = global_context.calculate_signature(
                bob_identity.private, bob_signed_pre_key.public.serialize());

            PreKeyBundle bundle = create_pre_key_bundle(
                bob_store.local_registration_id, 1, 31337, bob_pre_key.public,
                22, bob_signed_pre_key.public, sig, bob_identity.public);

            builder.process_pre_key_bundle(bundle);

            SessionRecord record = alice_store.load_session(bob_address);
            SessionCipher cipher = alice_store.create_session_cipher(bob_address);

            fail_if_not_eq_int(
                (int)cipher.get_session_version(),
                (int)record.state.session_version,
                "XEP-0384: cipher version must match record version");

        } catch (Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384: SessionCipher without session throws SG_ERR_NO_SESSION.
     *
     * If encrypt_key is called without a session, get_session_version()
     * throws before the guard is even evaluated. This documents the behavior.
     */
    private void test_no_session_version() {
        try {
            Store store = setup_test_store_context(global_context);
            // No session established for bob_address
            fail_if(store.contains_session(bob_address),
                "XEP-0384: no session should exist yet");

            SessionCipher cipher = store.create_session_cipher(bob_address);
            try {
                cipher.get_session_version();
                // If we get here without exception, the guard can't protect
                GLib.Test.message("XEP-0384: get_session_version() did not throw for no-session — guard unreachable");
                GLib.Test.fail();
            } catch (Error e) {
                // Expected: libomemo-c throws SG_ERR_NO_SESSION
                // This means encrypt_key would also fail before reaching the guard
            }
        } catch (Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }
}

}
