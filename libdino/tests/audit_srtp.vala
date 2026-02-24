using Gee;

namespace Dino.Test {

/**
 * RFC 3711: SRTP/SRTCP -- Crypto.Srtp.Session unit tests
 *
 * Tests the SRTP wrapper in crypto-vala/src/srtp.vala:
 *   - Key setup: has_encrypt/has_decrypt flags
 *   - RTP encrypt → decrypt roundtrip (AES_CM_128_HMAC_SHA1_80)
 *   - RTCP encrypt → decrypt roundtrip
 *   - Authentication: wrong key → AUTHENTICATION_FAILED
 *   - Ciphertext differs from plaintext (IND-CPA)
 *   - force_reset_encrypt_stream re-applies key
 */
class SrtpAudit : Gee.TestCase {

    public SrtpAudit() {
        base("SrtpAudit");

        // --- Session lifecycle ---
        add_test("RFC3711_session_initial_state", test_session_initial_state);
        add_test("RFC3711_session_has_encrypt_after_key", test_has_encrypt_after_key);
        add_test("RFC3711_session_has_decrypt_after_key", test_has_decrypt_after_key);

        // --- RTP roundtrip ---
        add_test("RFC3711_rtp_encrypt_decrypt_roundtrip", test_rtp_roundtrip);
        add_test("RFC3711_rtp_ciphertext_differs_from_plaintext", test_rtp_ciphertext_not_plaintext);
        add_test("RFC3711_rtp_ciphertext_longer_than_plaintext", test_rtp_ciphertext_longer);
        add_test("RFC3711_rtp_wrong_key_rejects", test_rtp_wrong_key_rejects);

        // --- RTCP roundtrip ---
        add_test("RFC3711_rtcp_encrypt_decrypt_roundtrip", test_rtcp_roundtrip);
        add_test("RFC3711_rtcp_wrong_key_rejects", test_rtcp_wrong_key_rejects);

        // --- force_reset_encrypt_stream ---
        add_test("RFC3711_force_reset_preserves_key", test_force_reset_preserves_key);
    }

    // ===================== Constants =====================

    // AES-128-CM requires 16-byte key + 14-byte salt = 30 bytes total
    private const int KEY_LEN = 16;
    private const int SALT_LEN = 14;

    // Minimal valid RTP header (12 bytes): V=2, PT=0, SeqNum=1, Timestamp=0, SSRC=0x12345678
    private uint8[] make_rtp_packet(uint16 seq_num = 1, uint8 payload_type = 0) {
        uint8[] packet = new uint8[12 + 160]; // 12-byte header + 160-byte payload (20ms G.711)

        // RTP header
        packet[0] = 0x80;  // V=2, P=0, X=0, CC=0
        packet[1] = payload_type & 0x7F;  // M=0, PT
        packet[2] = (uint8)((seq_num >> 8) & 0xFF);
        packet[3] = (uint8)(seq_num & 0xFF);
        // Timestamp (bytes 4-7): 0
        // SSRC (bytes 8-11): 0x12345678
        packet[8] = 0x12;
        packet[9] = 0x34;
        packet[10] = 0x56;
        packet[11] = 0x78;

        // Fill payload with recognizable pattern
        for (int i = 12; i < packet.length; i++) {
            packet[i] = (uint8)(i & 0xFF);
        }
        return packet;
    }

    // Minimal valid RTCP packet (8 bytes): V=2, PT=200 (SR), Length=1, SSRC=0x12345678
    private uint8[] make_rtcp_packet() {
        uint8[] packet = new uint8[28]; // Minimal Sender Report

        packet[0] = 0x80;  // V=2, P=0, RC=0
        packet[1] = 200;   // PT=SR
        packet[2] = 0x00;  // Length (in 32-bit words minus 1)
        packet[3] = 0x06;  // 6 = 28 bytes total / 4 - 1
        // SSRC
        packet[4] = 0x12;
        packet[5] = 0x34;
        packet[6] = 0x56;
        packet[7] = 0x78;
        // Rest is NTP timestamp + sender info (zeros fine for test)
        return packet;
    }

    private uint8[] make_key() {
        uint8[] key = new uint8[KEY_LEN];
        for (int i = 0; i < KEY_LEN; i++) key[i] = (uint8)(0xA0 + i);
        return key;
    }

    private uint8[] make_salt() {
        uint8[] salt = new uint8[SALT_LEN];
        for (int i = 0; i < SALT_LEN; i++) salt[i] = (uint8)(0xB0 + i);
        return salt;
    }

    private uint8[] make_wrong_key() {
        uint8[] key = new uint8[KEY_LEN];
        for (int i = 0; i < KEY_LEN; i++) key[i] = (uint8)(0xC0 + i);
        return key;
    }

    // ===================== Session lifecycle =====================

    private void test_session_initial_state() {
        var session = new Crypto.Srtp.Session();
        fail_if(session.has_encrypt, "RFC 3711: new session MUST NOT have encrypt before key set");
        fail_if(session.has_decrypt, "RFC 3711: new session MUST NOT have decrypt before key set");
    }

    private void test_has_encrypt_after_key() {
        var session = new Crypto.Srtp.Session();
        session.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());
        fail_if_not(session.has_encrypt, "RFC 3711: has_encrypt MUST be true after set_encryption_key");
    }

    private void test_has_decrypt_after_key() {
        var session = new Crypto.Srtp.Session();
        session.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());
        fail_if_not(session.has_decrypt, "RFC 3711: has_decrypt MUST be true after set_decryption_key");
    }

    // ===================== RTP roundtrip =====================

    private void test_rtp_roundtrip() {
        try {
            var sender = new Crypto.Srtp.Session();
            var receiver = new Crypto.Srtp.Session();

            uint8[] key = make_key();
            uint8[] salt = make_salt();
            sender.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);
            receiver.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);

            uint8[] plain = make_rtp_packet(1);
            uint8[] encrypted = sender.encrypt_rtp(plain);
            uint8[] decrypted = receiver.decrypt_rtp(encrypted);

            fail_if(decrypted.length != plain.length, @"RFC 3711: RTP roundtrip length mismatch: $(decrypted.length) != $(plain.length)");
            for (int i = 0; i < plain.length; i++) {
                if (plain[i] != decrypted[i]) {
                    fail_if_reached(@"RFC 3711: RTP roundtrip mismatch at byte $i: expected $(plain[i]), got $(decrypted[i])");
                    return;
                }
            }
        } catch (Crypto.Error e) {
            fail_if_reached(@"RFC 3711 RTP roundtrip error: $(e.message)");
        }
    }

    private void test_rtp_ciphertext_not_plaintext() {
        try {
            var session = new Crypto.Srtp.Session();
            session.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());

            uint8[] plain = make_rtp_packet(1);
            uint8[] encrypted = session.encrypt_rtp(plain);

            // At least the payload portion (after 12-byte header) MUST differ
            bool all_same = true;
            for (int i = 12; i < plain.length && i < encrypted.length; i++) {
                if (plain[i] != encrypted[i]) {
                    all_same = false;
                    break;
                }
            }
            fail_if(all_same, "RFC 3711: SRTP ciphertext payload MUST differ from plaintext (IND-CPA)");
        } catch (Crypto.Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_rtp_ciphertext_longer() {
        try {
            var session = new Crypto.Srtp.Session();
            session.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());

            uint8[] plain = make_rtp_packet(1);
            uint8[] encrypted = session.encrypt_rtp(plain);

            // AES_CM_128_HMAC_SHA1_80 appends 10-byte auth tag
            fail_if(encrypted.length <= plain.length,
                    "RFC 3711: SRTP ciphertext MUST be longer than plaintext (auth tag appended)");
            // Expected: plain.length + 10 (HMAC-SHA1-80 = 80 bits = 10 bytes)
            fail_if(encrypted.length != plain.length + 10,
                    @"RFC 3711: Expected length $(plain.length + 10), got $(encrypted.length)");
        } catch (Crypto.Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_rtp_wrong_key_rejects() {
        try {
            var sender = new Crypto.Srtp.Session();
            var receiver = new Crypto.Srtp.Session();

            sender.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());
            // Different key for receiver
            receiver.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_wrong_key(), make_salt());

            uint8[] plain = make_rtp_packet(1);
            uint8[] encrypted = sender.encrypt_rtp(plain);

            try {
                receiver.decrypt_rtp(encrypted);
                fail_if_reached("RFC 3711: SRTP decrypt with wrong key MUST throw AUTHENTICATION_FAILED");
            } catch (Crypto.Error e) {
                // Expected: AUTHENTICATION_FAILED
                fail_if_not(e is Crypto.Error.AUTHENTICATION_FAILED,
                           @"RFC 3711: Expected AUTHENTICATION_FAILED, got: $(e.message)");
            }
        } catch (Crypto.Error e) {
            fail_if_reached(@"Unexpected error during encrypt: $(e.message)");
        }
    }

    // ===================== RTCP roundtrip =====================

    private void test_rtcp_roundtrip() {
        try {
            var sender = new Crypto.Srtp.Session();
            var receiver = new Crypto.Srtp.Session();

            uint8[] key = make_key();
            uint8[] salt = make_salt();
            sender.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);
            receiver.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);

            uint8[] plain = make_rtcp_packet();
            uint8[] encrypted = sender.encrypt_rtcp(plain);
            uint8[] decrypted = receiver.decrypt_rtcp(encrypted);

            fail_if(decrypted.length != plain.length, @"RFC 3711: RTCP roundtrip length mismatch: $(decrypted.length) != $(plain.length)");
            for (int i = 0; i < plain.length; i++) {
                if (plain[i] != decrypted[i]) {
                    fail_if_reached(@"RFC 3711: RTCP roundtrip mismatch at byte $i");
                    return;
                }
            }
        } catch (Crypto.Error e) {
            fail_if_reached(@"RFC 3711 RTCP roundtrip error: $(e.message)");
        }
    }

    private void test_rtcp_wrong_key_rejects() {
        try {
            var sender = new Crypto.Srtp.Session();
            var receiver = new Crypto.Srtp.Session();

            sender.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_key(), make_salt());
            receiver.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, make_wrong_key(), make_salt());

            uint8[] plain = make_rtcp_packet();
            uint8[] encrypted = sender.encrypt_rtcp(plain);

            try {
                receiver.decrypt_rtcp(encrypted);
                fail_if_reached("RFC 3711: SRTCP decrypt with wrong key MUST throw AUTHENTICATION_FAILED");
            } catch (Crypto.Error e) {
                fail_if_not(e is Crypto.Error.AUTHENTICATION_FAILED,
                           @"RFC 3711: Expected AUTHENTICATION_FAILED, got: $(e.message)");
            }
        } catch (Crypto.Error e) {
            fail_if_reached(@"Unexpected error during encrypt: $(e.message)");
        }
    }

    // ===================== force_reset =====================

    private void test_force_reset_preserves_key() {
        try {
            var session = new Crypto.Srtp.Session();
            var receiver = new Crypto.Srtp.Session();

            uint8[] key = make_key();
            uint8[] salt = make_salt();
            session.set_encryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);
            receiver.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);

            // Encrypt one packet, then reset
            uint8[] p1 = make_rtp_packet(1);
            session.encrypt_rtp(p1);

            session.force_reset_encrypt_stream();

            // After reset, should still be able to encrypt and receiver should decrypt
            // (new context with same key, sequence counter reset)
            uint8[] p2 = make_rtp_packet(1);  // same seq num since context is reset
            uint8[] enc2 = session.encrypt_rtp(p2);

            // Receiver needs fresh context too since seq numbers reset
            var receiver2 = new Crypto.Srtp.Session();
            receiver2.set_decryption_key(Crypto.Srtp.AES_CM_128_HMAC_SHA1_80, key, salt);
            uint8[] dec2 = receiver2.decrypt_rtp(enc2);

            fail_if(dec2.length != p2.length, @"RFC 3711: force_reset roundtrip length mismatch: $(dec2.length) != $(p2.length)");
            for (int i = 0; i < p2.length; i++) {
                if (p2[i] != dec2[i]) {
                    fail_if_reached(@"RFC 3711: force_reset roundtrip mismatch at byte $i");
                    return;
                }
            }
        } catch (Crypto.Error e) {
            fail_if_reached(@"force_reset error: $(e.message)");
        }
    }
}

}
