using Srtp;

namespace Crypto.Srtp {
public const string AES_CM_128_HMAC_SHA1_80 = "AES_CM_128_HMAC_SHA1_80";
public const string AES_CM_128_HMAC_SHA1_32 = "AES_CM_128_HMAC_SHA1_32";
public const string F8_128_HMAC_SHA1_80 = "F8_128_HMAC_SHA1_80";

public class Session {
    public bool has_encrypt { get; private set; default = false; }
    public bool has_decrypt { get; private set; default = false; }

    private Context encrypt_context;
    private Context decrypt_context;

    static construct {
        init();
        install_log_handler(log);
    }

    private static void log(LogLevel level, string msg) {
        debug(@"SRTP[$level]: $msg");
    }

    public Session() {
        Context.create(out encrypt_context, null);
        Context.create(out decrypt_context, null);
    }

    public uint8[] encrypt_rtp(uint8[] data) throws Error {
        uint8[] buf = new uint8[data.length + MAX_TRAILER_LEN];
        Memory.copy(buf, data, data.length);
        int buf_use = data.length;
        ErrorStatus res = encrypt_context.protect(buf, ref buf_use);
        if (res != ErrorStatus.ok) {
            throw new Error.UNKNOWN(@"SRTP encrypt failed: $res");
        }
        buf.length = buf_use;
        return buf;
    }

    public uint8[] decrypt_rtp(uint8[] data) throws Error {
        uint8[] buf = new uint8[data.length];
        Memory.copy(buf, data, data.length);
        int buf_use = data.length;
        ErrorStatus res = decrypt_context.unprotect(buf, ref buf_use);
        switch (res) {
            case ErrorStatus.auth_fail:
                throw new Error.AUTHENTICATION_FAILED("SRTP packet failed the message authentication check");
            case ErrorStatus.ok:
                break;
            default:
                throw new Error.UNKNOWN(@"SRTP decrypt failed: $res");
        }
        buf.length = buf_use;
        return buf;
    }

    public uint8[] encrypt_rtcp(uint8[] data) throws Error {
        uint8[] buf = new uint8[data.length + MAX_TRAILER_LEN + 4];
        Memory.copy(buf, data, data.length);
        int buf_use = data.length;
        ErrorStatus res = encrypt_context.protect_rtcp(buf, ref buf_use);
        if (res != ErrorStatus.ok) {
            throw new Error.UNKNOWN(@"SRTCP encrypt failed: $res");
        }
        buf.length = buf_use;
        return buf;
    }

    public uint8[] decrypt_rtcp(uint8[] data) throws Error {
        uint8[] buf = new uint8[data.length];
        Memory.copy(buf, data, data.length);
        int buf_use = data.length;
        ErrorStatus res = decrypt_context.unprotect_rtcp(buf, ref buf_use);
        switch (res) {
            case ErrorStatus.auth_fail:
                throw new Error.AUTHENTICATION_FAILED("SRTCP packet failed the message authentication check");
            case ErrorStatus.ok:
                break;
            default:
                throw new Error.UNKNOWN(@"SRTCP decrypt failed: $res");
        }
        buf.length = buf_use;
        return buf;
    }

    private Policy create_policy(string profile) {
        Policy policy = Policy();
        switch (profile) {
            case AES_CM_128_HMAC_SHA1_80:
                policy.rtp.set_aes_cm_128_hmac_sha1_80();
                policy.rtcp.set_aes_cm_128_hmac_sha1_80();
                break;
            case AES_CM_128_HMAC_SHA1_32:
                policy.rtp.set_aes_cm_128_hmac_sha1_32();
                policy.rtcp.set_aes_cm_128_hmac_sha1_32();
                break;
            default:
                warning("SRTP create_policy: unsupported profile '%s', using default", profile);
                policy.rtp.set_rtp_default();
                policy.rtcp.set_rtcp_default();
                break;
        }
        return policy;
    }

    private string? last_encryption_profile = null;
    private uint8[]? last_encryption_key = null;
    private uint8[]? last_encryption_salt = null;

    public void force_reset_encrypt_stream() {
        if (last_encryption_profile == null) return;

        // Copy key/salt before recreation to avoid self-reference issues
        string profile = last_encryption_profile;
        uint8[] key = new uint8[last_encryption_key.length];
        Memory.copy(key, last_encryption_key, last_encryption_key.length);
        uint8[] salt = new uint8[last_encryption_salt.length];
        Memory.copy(salt, last_encryption_salt, last_encryption_salt.length);

        encrypt_context = null;
        Context.create(out encrypt_context, null);
        set_encryption_key(profile, key, salt);
    }

    public void set_encryption_key(string profile, uint8[] key, uint8[] salt) {
        last_encryption_profile = profile;
        last_encryption_key = key;
        last_encryption_salt = salt;

        Policy policy = create_policy(profile);
        policy.ssrc.type = SsrcType.any_outbound;
        policy.key = new uint8[key.length + salt.length];
        Memory.copy(policy.key, key, key.length);
        Memory.copy(((uint8*)policy.key) + key.length, salt, salt.length);
        policy.next = null;
        ErrorStatus res = encrypt_context.add_stream(ref policy);
        if (res != ErrorStatus.ok) {
            warning("SRTP set_encryption_key: add_stream failed: %s", res.to_string());
        }
        has_encrypt = true;
    }

    public void set_decryption_key(string profile, uint8[] key, uint8[] salt) {
        Policy policy = create_policy(profile);
        policy.ssrc.type = SsrcType.any_inbound;
        policy.key = new uint8[key.length + salt.length];
        Memory.copy(policy.key, key, key.length);
        Memory.copy(((uint8*)policy.key) + key.length, salt, salt.length);
        policy.next = null;
        ErrorStatus res = decrypt_context.add_stream(ref policy);
        if (res != ErrorStatus.ok) {
            warning("SRTP set_decryption_key: add_stream failed: %s", res.to_string());
        }
        has_decrypt = true;
    }
}
}
