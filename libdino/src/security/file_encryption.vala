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
        size_t tag_buffer_filled = 0;
        
        // Initial fill of tag buffer
        yield input.read_all_async(tag_buffer, Priority.DEFAULT, cancellable, out bytes_read);
        tag_buffer_filled = bytes_read;
        
        if (tag_buffer_filled < TAG_SIZE) {
             throw new IOError.FAILED("Stream too short (missing Tag)");
        }

        while (true) {
            ssize_t n = yield input.read_async(buffer, Priority.DEFAULT, cancellable);
            if (n == 0) break; // EOF
            
            // The bytes in 'tag_buffer' are now confirmed to be ciphertext (not tag), 
            // because we read more bytes.
            // Decrypt 'tag_buffer' and write it out.
            uint8[] out_chunk = new uint8[TAG_SIZE];
            cipher.decrypt(out_chunk, tag_buffer);
            yield output.write_all_async(out_chunk, Priority.DEFAULT, cancellable, null);
            
            // Now we have 'n' new bytes in 'buffer'.
            // We need to keep the last TAG_SIZE bytes of this new chunk (plus potentially some from previous if n is small)
            // as the new potential tag.
            
            // To simplify:
            // We have 'tag_buffer' (old potential tag) and 'buffer' (new data).
            // We already processed 'tag_buffer'.
            // Now we need to refill 'tag_buffer' from the end of 'buffer'.
            // And decrypt the rest of 'buffer'.
            
            // Wait, the logic above is slightly flawed.
            // Correct logic:
            // 1. We have a "holding buffer" of size TAG_SIZE.
            // 2. We read a chunk.
            // 3. If chunk size > 0:
            //    a. We decrypt the *previous* holding buffer and write it.
            //    b. We take the *last* TAG_SIZE bytes of the new chunk as the new holding buffer.
            //    c. We decrypt the *rest* of the new chunk (beginning) and write it.
            //    d. Wait, what if chunk < TAG_SIZE?
            
            // Better Logic:
            // Use a circular buffer or just a large buffer.
            // Let's use a simpler approach:
            // Read everything into a temporary file? No, we want to stream to output (which might be a temp file).
            
            // Let's use the "Hold Back" strategy properly.
            // We need to hold back exactly TAG_SIZE bytes.
            
            // Current state: 'tag_buffer' holds the last TAG_SIZE bytes seen so far.
            // We just read 'n' bytes into 'buffer'.
            
            if (n >= TAG_SIZE) {
                // 1. Decrypt and write the old 'tag_buffer'.
                // (We already did this? No, we need to do it now).
                // Actually, in the loop:
                // We have 'tag_buffer' filled with valid data from previous reads.
                // We read 'n' new bytes.
                // Since we have new bytes, 'tag_buffer' is definitely ciphertext.
                // Decrypt 'tag_buffer' -> write.
                
                // 2. Decrypt 'buffer[0 : n - TAG_SIZE]' -> write.
                uint8[] middle_chunk = buffer[0 : (int)n - TAG_SIZE];
                uint8[] out_middle = new uint8[middle_chunk.length];
                cipher.decrypt(out_middle, middle_chunk);
                yield output.write_all_async(out_middle, Priority.DEFAULT, cancellable, null);
                
                // 3. Update 'tag_buffer' with 'buffer[n - TAG_SIZE : n]'.
                Memory.copy(tag_buffer, (void*)((uint8*)buffer + (n - TAG_SIZE)), TAG_SIZE);
            } else {
                // New chunk is smaller than TAG_SIZE.
                // We need to slide data.
                // We have TAG_SIZE bytes in tag_buffer.
                // We have n bytes in buffer.
                // Total available: TAG_SIZE + n.
                // New tag will be the last TAG_SIZE bytes of (tag_buffer + buffer).
                // Data to decrypt is the first 'n' bytes of (tag_buffer + buffer).
                
                uint8[] combined = new uint8[TAG_SIZE + n];
                Memory.copy(combined, tag_buffer, TAG_SIZE);
                Memory.copy((void*)((uint8*)combined + TAG_SIZE), buffer, (size_t)n);
                
                // Decrypt first 'n' bytes
                uint8[] to_decrypt = combined[0:(int)n];
                uint8[] out_decrypt = new uint8[(int)n];
                cipher.decrypt(out_decrypt, to_decrypt);
                yield output.write_all_async(out_decrypt, Priority.DEFAULT, cancellable, null);
                
                // New tag is last TAG_SIZE bytes
                Memory.copy(tag_buffer, (void*)((uint8*)combined + n), TAG_SIZE);
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
