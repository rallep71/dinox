/*
 * Copyright (C) 2026 DinoX Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using GLib;
using Crypto;

namespace Dino.Security {

public class FileEncryption : Object {
    private const int SALT_SIZE = 16;       // 128-bit random salt per NIST SP 800-132
    private const int IV_SIZE = 12;
    private const int TAG_SIZE = 16;
    private const int KDF_ITERATIONS = 100000;  // NIST SP 800-132 recommends ≥10,000

    // Legacy (pre-v1.1.2.7) constants for backwards-compatible decryption
    private const int LEGACY_SALT_SIZE = 8;    // was 64-bit salt
    private const int LEGACY_IV_SIZE = 16;     // was 128-bit IV
    private const int LEGACY_TAG_SIZE = 8;     // was 64-bit tag

    private string password_store;

    /**
     * Set to true when decrypt_data() falls back to legacy format.
     * Callers can check this to re-encrypt with current format.
     */
    public bool last_decrypt_used_legacy { get; private set; default = false; }

    public FileEncryption(string password) {
        this.password_store = password;
    }

    /*
     * PBKDF2-SHA256 key derivation (NIST SP 800-132 compliant).
     * Uses random salt and 100,000 iterations.
     */
    private static uint8[] derive_key(string password, uint8[] salt) {
        uint8[] password_bytes = (uint8[]) password.to_utf8();

        // PBKDF2-HMAC-SHA256, single block (output = 32 bytes = SHA256 size)
        uint8[] result = new uint8[32];
        uint8[] last = new uint8[salt.length + 4];
        Memory.copy(last, salt, salt.length);
        last[salt.length + 3] = 1;  // Block counter = 1

        for (int i = 0; i < KDF_ITERATIONS; i++) {
            // HMAC-SHA256(password, last)
            Hmac hmac = new Hmac(ChecksumType.SHA256, password_bytes);
            hmac.update(last);
            size_t out_len = 32;
            uint8[] step = new uint8[32];
            hmac.get_digest(step, ref out_len);
            last = step;

            // XOR into result
            for (int j = 0; j < 32; j++) {
                result[j] ^= step[j];
            }
        }
        return result;
    }

    public async void encrypt_stream(InputStream input, OutputStream output, Cancellable? cancellable = null) throws GLib.Error {
        // Generate random salt
        uint8[] salt = new uint8[SALT_SIZE];
        Crypto.randomize(salt);
        yield output.write_all_async(salt, Priority.DEFAULT, cancellable, null);

        // Derive key from password + salt
        uint8[] derived_key = derive_key(password_store, salt);

        // IV
        uint8[] iv = new uint8[IV_SIZE];
        Crypto.randomize(iv);
        yield output.write_all_async(iv, Priority.DEFAULT, cancellable, null);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(derived_key);
        cipher.set_iv(iv);

        uint8[] buffer = new uint8[8192];
        ssize_t read;
        while ((read = yield input.read_async(buffer, Priority.DEFAULT, cancellable)) > 0) {
            // Slice the buffer to the actual read size
            // We can't pass a slice to 'encrypt' if it expects an array of matching size for output
            // But 'encrypt' takes (output, input).
            // We need to make sure output buffer is large enough.
            
            // Optimization: Use a temporary buffer for the chunk if needed, or just pass the slice if Vala handles it.
            // Vala arrays pass length.
            
            uint8[] chunk = buffer[0:(int)read];
            uint8[] out_chunk = new uint8[(int)read];
            cipher.encrypt(out_chunk, chunk);
            yield output.write_all_async(out_chunk, Priority.DEFAULT, cancellable, null);
        }
        
        // Tag
        uint8[] tag = cipher.get_tag(TAG_SIZE);
        yield output.write_all_async(tag, Priority.DEFAULT, cancellable, null);
    }

    public async void decrypt_stream(InputStream input, OutputStream output, Cancellable? cancellable = null) throws GLib.Error {
        // Try current format first
        try {
            yield decrypt_stream_format(input, output, SALT_SIZE, IV_SIZE, TAG_SIZE, cancellable);
            return;
        } catch (GLib.Error e) {
            // If streams are seekable, try legacy format
            var seekable_in = input as Seekable;
            var seekable_out = output as Seekable;
            if (seekable_in != null && seekable_in.can_seek() &&
                seekable_out != null && seekable_out.can_seek()) {
                try {
                    seekable_in.seek(0, SeekType.SET);
                    seekable_out.seek(0, SeekType.SET);
                    seekable_out.truncate(0);
                    yield decrypt_stream_format(input, output, LEGACY_SALT_SIZE, LEGACY_IV_SIZE, LEGACY_TAG_SIZE, cancellable);
                    debug("Decrypted stream using legacy encryption format (pre-v1.1.2.7)");
                    return;
                } catch (GLib.Error e2) {
                    // Both failed, throw original error
                }
            }
            throw e;
        }
    }

    private async void decrypt_stream_format(InputStream input, OutputStream output, int salt_sz, int iv_sz, int tag_sz, Cancellable? cancellable = null) throws GLib.Error {
        // Read Salt
        uint8[] salt = new uint8[salt_sz];
        size_t bytes_read;
        yield input.read_all_async(salt, Priority.DEFAULT, cancellable, out bytes_read);
        if (bytes_read != salt_sz) throw new IOError.FAILED("Stream too short (missing Salt)");

        // Read IV
        uint8[] iv = new uint8[iv_sz];
        yield input.read_all_async(iv, Priority.DEFAULT, cancellable, out bytes_read);
        if (bytes_read != iv_sz) throw new IOError.FAILED("Stream too short (missing IV)");

        // Derive key from password + salt
        uint8[] derived_key = derive_key(password_store, salt);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(derived_key);
        cipher.set_iv(iv);

        // We need to read until the end to get the tag.
        // The last tag_sz bytes are the tag.
        // This is tricky in a stream because we don't know when it ends until it ends.
        // We need a rolling buffer or lookahead.
        
        // Strategy:
        // Maintain a buffer of size tag_sz + CHUNK_SIZE.
        // Always keep tag_sz bytes "held back" as potential tag.
        
        uint8[] buffer = new uint8[8192];
        uint8[] tag_buffer = new uint8[tag_sz];
        
        // Initial fill of tag buffer (holdback for potential GCM tag at EOF)
        yield input.read_all_async(tag_buffer, Priority.DEFAULT, cancellable, out bytes_read);
        
        if (bytes_read < tag_sz) {
             throw new IOError.FAILED("Stream too short (missing Tag)");
        }

        while (true) {
            ssize_t n = yield input.read_async(buffer, Priority.DEFAULT, cancellable);
            if (n == 0) break; // EOF

            // tag_buffer holds tag_sz bytes from previous reads (potential tag).
            // We now have n new bytes in buffer. Total: tag_sz + n bytes.
            // The first n bytes are confirmed ciphertext, last tag_sz are new holdback.

            if (n >= tag_sz) {
                // Decrypt all of tag_buffer (confirmed ciphertext)
                uint8[] out_held = new uint8[tag_sz];
                cipher.decrypt(out_held, tag_buffer);
                yield output.write_all_async(out_held, Priority.DEFAULT, cancellable, null);

                // Decrypt buffer[0 : n - tag_sz]
                int middle_len = (int)n - tag_sz;
                if (middle_len > 0) {
                    uint8[] middle = buffer[0:middle_len];
                    uint8[] out_middle = new uint8[middle_len];
                    cipher.decrypt(out_middle, middle);
                    yield output.write_all_async(out_middle, Priority.DEFAULT, cancellable, null);
                }

                // New tag_buffer = buffer[n - tag_sz : n]
                Memory.copy(tag_buffer, (void*)((uint8*)buffer + (n - tag_sz)), tag_sz);
            } else {
                // n < tag_sz: decrypt only the first n bytes of tag_buffer,
                // then slide remaining tag_buffer bytes + new buffer bytes into new holdback.
                uint8[] to_decrypt = tag_buffer[0:(int)n];
                uint8[] out_decrypt = new uint8[(int)n];
                cipher.decrypt(out_decrypt, to_decrypt);
                yield output.write_all_async(out_decrypt, Priority.DEFAULT, cancellable, null);

                // New tag_buffer = tag_buffer[n:tag_sz] + buffer[0:n]
                uint8[] new_tag = new uint8[tag_sz];
                int keep = tag_sz - (int)n;
                Memory.copy(new_tag, (void*)((uint8*)tag_buffer + n), (size_t)keep);
                Memory.copy((void*)((uint8*)new_tag + keep), buffer, (size_t)n);
                Memory.copy(tag_buffer, new_tag, tag_sz);
            }
        }
        
        // Loop finished. 'tag_buffer' contains the Tag.
        cipher.check_tag(tag_buffer);
    }

    /**
     * Decrypt data, automatically falling back to legacy (pre-v1.1.2.7) format
     * if the current format fails. Sets last_decrypt_used_legacy accordingly.
     */
    public uint8[] decrypt_data(uint8[] encrypted_data) throws GLib.Error {
        last_decrypt_used_legacy = false;

        // Try current format first: SALT(16) + IV(12) + Ciphertext + Tag(16)
        try {
            return decrypt_data_format(encrypted_data, SALT_SIZE, IV_SIZE, TAG_SIZE);
        } catch (GLib.Error e) {
            // Fall back to legacy format (pre-v1.1.2.7): SALT(8) + IV(16) + Ciphertext + Tag(8)
            try {
                uint8[] result = decrypt_data_format(encrypted_data, LEGACY_SALT_SIZE, LEGACY_IV_SIZE, LEGACY_TAG_SIZE);
                last_decrypt_used_legacy = true;
                debug("Decrypted data using legacy encryption format (pre-v1.1.2.7)");
                return result;
            } catch (GLib.Error e2) {
                throw e; // Re-throw original (current format) error
            }
        }
    }

    private uint8[] decrypt_data_format(uint8[] encrypted_data, int salt_sz, int iv_sz, int tag_sz) throws GLib.Error {
        int overhead = salt_sz + iv_sz + tag_sz;
        if (encrypted_data.length < overhead) {
            throw new IOError.FAILED("Data too short");
        }

        uint8[] salt = encrypted_data[0:salt_sz];
        uint8[] iv = encrypted_data[salt_sz:salt_sz + iv_sz];
        uint8[] tag = encrypted_data[encrypted_data.length - tag_sz:encrypted_data.length];
        uint8[] ciphertext = encrypted_data[salt_sz + iv_sz:encrypted_data.length - tag_sz];

        uint8[] derived_key = derive_key(password_store, salt);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(derived_key);
        cipher.set_iv(iv);

        uint8[] plaintext = new uint8[ciphertext.length];
        cipher.decrypt(plaintext, ciphertext);
        cipher.check_tag(tag);

        return plaintext;
    }
    
    public uint8[] encrypt_data(uint8[] plaintext) throws GLib.Error {
        // Generate random salt (NIST SP 800-132)
        uint8[] salt = new uint8[SALT_SIZE];
        Crypto.randomize(salt);

        // Derive key from password + random salt
        uint8[] derived_key = derive_key(password_store, salt);

        uint8[] iv = new uint8[IV_SIZE];
        Crypto.randomize(iv);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(derived_key);
        cipher.set_iv(iv);

        uint8[] ciphertext = new uint8[plaintext.length];
        cipher.encrypt(ciphertext, plaintext);
        uint8[] tag = cipher.get_tag(TAG_SIZE);

        // Result: Salt(16) + IV(12) + Ciphertext + Tag(16)
        uint8[] result = new uint8[SALT_SIZE + IV_SIZE + ciphertext.length + TAG_SIZE];
        Memory.copy(result, salt, SALT_SIZE);
        Memory.copy((void*)((uint8*)result + SALT_SIZE), iv, IV_SIZE);
        Memory.copy((void*)((uint8*)result + SALT_SIZE + IV_SIZE), ciphertext, ciphertext.length);
        Memory.copy((void*)((uint8*)result + SALT_SIZE + IV_SIZE + ciphertext.length), tag, TAG_SIZE);
        
        return result;
    }

    /**
     * Encrypt data using legacy (pre-v1.1.2.7) format for testing purposes.
     * Format: SALT(8) + IV(16) + Ciphertext + TAG(8)
     * This method is ONLY for verifying that decrypt_data() correctly falls
     * back to LEGACY_SALT_SIZE/LEGACY_IV_SIZE/LEGACY_TAG_SIZE.
     */
    public uint8[] encrypt_data_legacy(uint8[] plaintext) throws GLib.Error {
        uint8[] salt = new uint8[LEGACY_SALT_SIZE];
        Crypto.randomize(salt);

        uint8[] derived_key = derive_key(password_store, salt);

        uint8[] iv = new uint8[LEGACY_IV_SIZE];
        Crypto.randomize(iv);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(derived_key);
        cipher.set_iv(iv);

        uint8[] ciphertext = new uint8[plaintext.length];
        cipher.encrypt(ciphertext, plaintext);
        uint8[] tag = cipher.get_tag(LEGACY_TAG_SIZE);

        // Legacy format: SALT(8) + IV(16) + Ciphertext + TAG(8)
        int overhead = LEGACY_SALT_SIZE + LEGACY_IV_SIZE + LEGACY_TAG_SIZE;
        uint8[] result = new uint8[overhead + ciphertext.length];
        Memory.copy(result, salt, LEGACY_SALT_SIZE);
        Memory.copy((void*)((uint8*)result + LEGACY_SALT_SIZE), iv, LEGACY_IV_SIZE);
        Memory.copy((void*)((uint8*)result + LEGACY_SALT_SIZE + LEGACY_IV_SIZE), ciphertext, ciphertext.length);
        Memory.copy((void*)((uint8*)result + LEGACY_SALT_SIZE + LEGACY_IV_SIZE + ciphertext.length), tag, LEGACY_TAG_SIZE);

        return result;
    }
}

}
