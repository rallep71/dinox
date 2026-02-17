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
    private uint8[] key;
    private const string SALT = "DinoX File Encryption v1";
    private const int IV_SIZE = 12;
    private const int TAG_SIZE = 16;

    public FileEncryption(string password) {
        this.key = derive_key(password);
    }

    private uint8[] derive_key(string password) {
        Checksum checksum = new Checksum(ChecksumType.SHA256);
        checksum.update(password.data, password.length);
        checksum.update(SALT.data, SALT.length);
        
        uint8[] digest = new uint8[32]; // SHA256 is 32 bytes
        size_t len = 32;
        checksum.get_digest(digest, ref len);
        return digest;
    }

    public async void encrypt_stream(InputStream input, OutputStream output, Cancellable? cancellable = null) throws GLib.Error {
        // IV
        uint8[] iv = new uint8[IV_SIZE];
        Crypto.randomize(iv);
        yield output.write_all_async(iv, Priority.DEFAULT, cancellable, null);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(this.key);
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
        // Read IV
        uint8[] iv = new uint8[IV_SIZE];
        size_t bytes_read;
        yield input.read_all_async(iv, Priority.DEFAULT, cancellable, out bytes_read);
        if (bytes_read != IV_SIZE) throw new IOError.FAILED("Stream too short (missing IV)");

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(this.key);
        cipher.set_iv(iv);

        // We need to read until the end to get the tag.
        // The last TAG_SIZE bytes are the tag.
        // This is tricky in a stream because we don't know when it ends until it ends.
        // We need a rolling buffer or lookahead.
        
        // Strategy:
        // Maintain a buffer of size TAG_SIZE + CHUNK_SIZE.
        // Always keep TAG_SIZE bytes "held back" as potential tag.
        
        uint8[] buffer = new uint8[8192];
        uint8[] tag_buffer = new uint8[TAG_SIZE];
        
        // Initial fill of tag buffer (holdback for potential GCM tag at EOF)
        yield input.read_all_async(tag_buffer, Priority.DEFAULT, cancellable, out bytes_read);
        
        if (bytes_read < TAG_SIZE) {
             throw new IOError.FAILED("Stream too short (missing Tag)");
        }

        while (true) {
            ssize_t n = yield input.read_async(buffer, Priority.DEFAULT, cancellable);
            if (n == 0) break; // EOF

            // tag_buffer holds TAG_SIZE bytes from previous reads (potential tag).
            // We now have n new bytes in buffer. Total: TAG_SIZE + n bytes.
            // The first n bytes are confirmed ciphertext, last TAG_SIZE are new holdback.

            if (n >= TAG_SIZE) {
                // Decrypt all of tag_buffer (confirmed ciphertext)
                uint8[] out_held = new uint8[TAG_SIZE];
                cipher.decrypt(out_held, tag_buffer);
                yield output.write_all_async(out_held, Priority.DEFAULT, cancellable, null);

                // Decrypt buffer[0 : n - TAG_SIZE]
                int middle_len = (int)n - TAG_SIZE;
                if (middle_len > 0) {
                    uint8[] middle = buffer[0:middle_len];
                    uint8[] out_middle = new uint8[middle_len];
                    cipher.decrypt(out_middle, middle);
                    yield output.write_all_async(out_middle, Priority.DEFAULT, cancellable, null);
                }

                // New tag_buffer = buffer[n - TAG_SIZE : n]
                Memory.copy(tag_buffer, (void*)((uint8*)buffer + (n - TAG_SIZE)), TAG_SIZE);
            } else {
                // n < TAG_SIZE: decrypt only the first n bytes of tag_buffer,
                // then slide remaining tag_buffer bytes + new buffer bytes into new holdback.
                uint8[] to_decrypt = tag_buffer[0:(int)n];
                uint8[] out_decrypt = new uint8[(int)n];
                cipher.decrypt(out_decrypt, to_decrypt);
                yield output.write_all_async(out_decrypt, Priority.DEFAULT, cancellable, null);

                // New tag_buffer = tag_buffer[n:TAG_SIZE] + buffer[0:n]
                uint8[] new_tag = new uint8[TAG_SIZE];
                int keep = TAG_SIZE - (int)n;
                Memory.copy(new_tag, (void*)((uint8*)tag_buffer + n), (size_t)keep);
                Memory.copy((void*)((uint8*)new_tag + keep), buffer, (size_t)n);
                Memory.copy(tag_buffer, new_tag, TAG_SIZE);
            }
        }
        
        // Loop finished. 'tag_buffer' contains the Tag.
        cipher.check_tag(tag_buffer);
    }

    public uint8[] decrypt_data(uint8[] encrypted_data) throws GLib.Error {
        if (encrypted_data.length < IV_SIZE + TAG_SIZE) {
            throw new IOError.FAILED("Data too short");
        }

        uint8[] iv = encrypted_data[0:IV_SIZE];
        // Tag is at the end
        uint8[] tag = encrypted_data[encrypted_data.length - TAG_SIZE:encrypted_data.length];
        uint8[] ciphertext = encrypted_data[IV_SIZE:encrypted_data.length - TAG_SIZE];

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(this.key);
        cipher.set_iv(iv);

        uint8[] plaintext = new uint8[ciphertext.length];
        cipher.decrypt(plaintext, ciphertext);
        cipher.check_tag(tag);

        return plaintext;
    }
    
    public uint8[] encrypt_data(uint8[] plaintext) throws GLib.Error {
        uint8[] iv = new uint8[IV_SIZE];
        Crypto.randomize(iv);

        var cipher = new SymmetricCipher("AES256-GCM");
        cipher.set_key(this.key);
        cipher.set_iv(iv);

        uint8[] ciphertext = new uint8[plaintext.length];
        cipher.encrypt(ciphertext, plaintext);
        uint8[] tag = cipher.get_tag(TAG_SIZE);

        // Result: IV + Ciphertext + Tag
        uint8[] result = new uint8[IV_SIZE + ciphertext.length + TAG_SIZE];
        Memory.copy(result, iv, IV_SIZE);
        Memory.copy((void*)((uint8*)result + IV_SIZE), ciphertext, ciphertext.length);
        Memory.copy((void*)((uint8*)result + IV_SIZE + ciphertext.length), tag, TAG_SIZE);
        
        return result;
    }
}

}
