using Dino.Plugins.Omemo;

/**
 * Security Logic Tests -- Tier 3 Security Audit
 *
 * Tests for three security-critical decision functions:
 *
 * 1. classify_prekey_update() -- Identity key change detection (Bug #19)
 *    CWE-295/322: Key change accepted without user confirmation
 *
 * 2. is_encrypt_result_safe_to_send() -- Encrypt error body validation
 *    CWE-311/319: Plaintext leak on encryption failure
 *
 * 3. classify_decrypt_failure_stage() -- Ratchet advance detection
 *    CWE-755: Inconsistent state on partial failure
 */

namespace Omemo.Test {

/* ================================================================
 * Suite 1: PreKeyUpdateClassifier (6 tests)
 * Target: classify_prekey_update() from update_db_for_prekey()
 * ================================================================ */
class PreKeyUpdateClassifierTest : Gee.TestCase {
    public PreKeyUpdateClassifierTest() {
        base("PreKeyUpdateClassifier");

        add_test("SEC_prekey_new_device", test_new_device);
        add_test("SEC_prekey_new_device_null_key", test_new_device_null_key);
        add_test("SEC_prekey_same_key_no_change", test_same_key_no_change);
        add_test("SEC_prekey_key_changed", test_key_changed);
        add_test("SEC_prekey_key_changed_is_not_no_change", test_key_changed_not_no_change);
        add_test("SEC_prekey_empty_vs_populated", test_empty_vs_populated);
    }

    /* New device (device_exists=false) → INSERT_NEW regardless of keys */
    void test_new_device() {
        var action = classify_prekey_update(null, "AAAA", false);
        fail_if_not(action == PreKeyUpdateAction.INSERT_NEW,
            "new device should be INSERT_NEW");
    }

    /* Device exists but stored key is null → INSERT_NEW (first key learn) */
    void test_new_device_null_key() {
        var action = classify_prekey_update(null, "BBBB", true);
        fail_if_not(action == PreKeyUpdateAction.INSERT_NEW,
            "existing device with null key should be INSERT_NEW");
    }

    /* Device exists, same key → NO_CHANGE */
    void test_same_key_no_change() {
        string key = "AAAABBBBCCCCDDDDEEEE";
        var action = classify_prekey_update(key, key, true);
        fail_if_not(action == PreKeyUpdateAction.NO_CHANGE,
            "same key should be NO_CHANGE");
    }

    /* Device exists, different key → KEY_CHANGED (Bug #19: accepted silently) */
    void test_key_changed() {
        var action = classify_prekey_update("OLD_KEY_BASE64", "NEW_KEY_BASE64", true);
        fail_if_not(action == PreKeyUpdateAction.KEY_CHANGED,
            "different key should be KEY_CHANGED");
    }

    /* KEY_CHANGED must NOT be classified as NO_CHANGE (regression guard) */
    void test_key_changed_not_no_change() {
        var action = classify_prekey_update("KEY_A", "KEY_B", true);
        fail_if(action == PreKeyUpdateAction.NO_CHANGE,
            "changed key must not be NO_CHANGE");
    }

    /* Empty string key vs populated key → KEY_CHANGED */
    void test_empty_vs_populated() {
        var action = classify_prekey_update("", "REAL_KEY", true);
        fail_if_not(action == PreKeyUpdateAction.KEY_CHANGED,
            "empty existing key vs real key should be KEY_CHANGED");
    }
}


/* ================================================================
 * Suite 2: EncryptSafetyCheck (8 tests)
 * Target: is_encrypt_result_safe_to_send() from encrypt()
 * ================================================================ */
class EncryptSafetyCheckTest : Gee.TestCase {
    public EncryptSafetyCheckTest() {
        base("EncryptSafetyCheck");

        add_test("SEC_encrypt_success_safe_to_send", test_success_safe);
        add_test("SEC_encrypt_failure_must_not_send", test_failure_not_safe);
        add_test("SEC_encrypt_null_body_not_safe", test_null_body);
        add_test("SEC_encrypt_plaintext_leak_detected", test_plaintext_leak);
        add_test("SEC_encrypt_error_body_not_safe", test_error_body);
        add_test("SEC_encrypt_success_null_original_ok", test_null_original);
        add_test("SEC_encrypt_false_with_marker_not_safe", test_false_with_marker);
        add_test("SEC_encrypt_true_with_error_body_not_safe", test_true_error_body);
    }

    /* encrypted=true, correct marker body → safe */
    void test_success_safe() {
        bool safe = is_encrypt_result_safe_to_send(
            true, "[This message is OMEMO encrypted]", "Hello secret!");
        fail_if_not(safe, "successful encryption should be safe to send");
    }

    /* encrypted=false → never safe, regardless of body */
    void test_failure_not_safe() {
        bool safe = is_encrypt_result_safe_to_send(
            false, "[OMEMO encryption failed]", "Hello secret!");
        fail_if(safe, "failed encryption must not be sent");
    }

    /* encrypted=true but body is null → not safe */
    void test_null_body() {
        bool safe = is_encrypt_result_safe_to_send(
            true, null, "Hello secret!");
        fail_if(safe, "null body should not be safe");
    }

    /* encrypted=true but body == original plaintext → CATASTROPHIC LEAK */
    void test_plaintext_leak() {
        string secret = "Transfer $50000 to account 12345";
        bool safe = is_encrypt_result_safe_to_send(true, secret, secret);
        fail_if(safe, "body == original plaintext is a catastrophic leak");
    }

    /* Body is the error string "[OMEMO encryption failed]" → not safe */
    void test_error_body() {
        bool safe = is_encrypt_result_safe_to_send(
            true, "[OMEMO encryption failed]", "secret");
        fail_if(safe, "error body should not be safe even if encrypted=true");
    }

    /* encrypted=true, marker body, original_body=null → safe (empty message) */
    void test_null_original() {
        bool safe = is_encrypt_result_safe_to_send(
            true, "[This message is OMEMO encrypted]", null);
        fail_if_not(safe, "null original body with marker should be safe");
    }

    /* encrypted=false but body is the correct marker → still not safe */
    void test_false_with_marker() {
        bool safe = is_encrypt_result_safe_to_send(
            false, "[This message is OMEMO encrypted]", "secret");
        fail_if(safe, "encrypted=false must not send even with marker body");
    }

    /* encrypted=true but body is error string → inconsistent state, not safe */
    void test_true_error_body() {
        bool safe = is_encrypt_result_safe_to_send(
            true, "[OMEMO encryption failed]", "secret");
        fail_if(safe, "error body with encrypted=true is inconsistent — not safe");
    }
}


/* ================================================================
 * Suite 3: DecryptFailureStageTest (12 tests)
 * Target: classify_decrypt_failure_stage() from decrypt_key_raw/decrypt_envelope
 * ================================================================ */
class DecryptFailureStageTest : Gee.TestCase {
    public DecryptFailureStageTest() {
        base("DecryptFailureStage");

        /* Pre-ratchet errors (safe to retry) */
        add_test("SEC_stage_no_session_pre_ratchet", test_no_session);
        add_test("SEC_stage_invalid_message_pre_ratchet", test_invalid_message);
        add_test("SEC_stage_legacy_message_pre_ratchet", test_legacy_message);
        add_test("SEC_stage_deserialize_pre_ratchet", test_deserialize);
        add_test("SEC_stage_db_update_failed_pre_ratchet", test_db_update);

        /* Post-ratchet errors (ratchet consumed, cannot retry) */
        add_test("SEC_stage_hmac_failed_post_ratchet", test_hmac_failed);
        add_test("SEC_stage_aes_failed_post_ratchet", test_aes_failed);
        add_test("SEC_stage_sce_parse_post_ratchet", test_sce_parse);
        add_test("SEC_stage_key_too_short_post_ratchet", test_key_short);
        add_test("SEC_stage_hkdf_failed_post_ratchet", test_hkdf_failed);
        add_test("SEC_stage_hmac_compute_post_ratchet", test_hmac_compute);

        /* Unknown error → conservative assumption */
        add_test("SEC_stage_unknown_error_assume_post", test_unknown);
    }

    /* --- Pre-ratchet (safe to retry) --- */

    void test_no_session() {
        var stage = classify_decrypt_failure_stage("SG_ERR_NO_SESSION for alice@example.com/1234");
        fail_if_not(stage == DecryptFailureStage.PRE_RATCHET,
            "SG_ERR_NO_SESSION should be PRE_RATCHET");
    }

    void test_invalid_message() {
        var stage = classify_decrypt_failure_stage("SG_ERR_INVALID_MESSAGE: bad format");
        fail_if_not(stage == DecryptFailureStage.PRE_RATCHET,
            "SG_ERR_INVALID_MESSAGE should be PRE_RATCHET");
    }

    void test_legacy_message() {
        var stage = classify_decrypt_failure_stage("SG_ERR_LEGACY_MESSAGE: version mismatch");
        fail_if_not(stage == DecryptFailureStage.PRE_RATCHET,
            "SG_ERR_LEGACY_MESSAGE should be PRE_RATCHET");
    }

    void test_deserialize() {
        var stage = classify_decrypt_failure_stage("Failed to deserialize pre-key message");
        fail_if_not(stage == DecryptFailureStage.PRE_RATCHET,
            "deserialize error should be PRE_RATCHET");
    }

    void test_db_update() {
        var stage = classify_decrypt_failure_stage("Failed updating db for prekey");
        fail_if_not(stage == DecryptFailureStage.PRE_RATCHET,
            "DB update failure should be PRE_RATCHET");
    }

    /* --- Post-ratchet (cannot retry) --- */

    void test_hmac_failed() {
        var stage = classify_decrypt_failure_stage("HMAC verification failed");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "HMAC verification failed should be POST_RATCHET");
    }

    void test_aes_failed() {
        var stage = classify_decrypt_failure_stage("AES-256-CBC decrypt failed");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "AES-256-CBC decrypt failed should be POST_RATCHET");
    }

    void test_sce_parse() {
        var stage = classify_decrypt_failure_stage("Failed to parse SCE envelope");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "SCE parse failure should be POST_RATCHET");
    }

    void test_key_short() {
        var stage = classify_decrypt_failure_stage("Decrypted key too short (got 16, need 48)");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "key too short should be POST_RATCHET");
    }

    void test_hkdf_failed() {
        var stage = classify_decrypt_failure_stage("HKDF failed");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "HKDF failed should be POST_RATCHET");
    }

    void test_hmac_compute() {
        var stage = classify_decrypt_failure_stage("HMAC computation failed");
        fail_if_not(stage == DecryptFailureStage.POST_RATCHET,
            "HMAC computation failed should be POST_RATCHET");
    }

    /* --- Unknown → conservative assumption --- */

    void test_unknown() {
        var stage = classify_decrypt_failure_stage("Something completely unexpected happened");
        fail_if_not(stage == DecryptFailureStage.UNKNOWN_ASSUME_POST,
            "unknown error should be UNKNOWN_ASSUME_POST (conservative)");
    }
}

} // namespace Omemo.Test
