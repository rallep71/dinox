/*
 * Copyright (C) 2026 DinoX Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using GLib;
using Gee;

namespace Dino {

public class ChecksumOutputStream : OutputStream {
    private class ChecksumWrapper {
        public Checksum c;
        public ChecksumWrapper(ChecksumType type) {
            c = new Checksum(type);
        }
    }
    private HashMap<ChecksumType, ChecksumWrapper> checksums = new HashMap<ChecksumType, ChecksumWrapper>();

    public ChecksumOutputStream(Gee.List<ChecksumType> types) {
        foreach (var type in types) {
            checksums[type] = new ChecksumWrapper(type);
        }
    }

    public override ssize_t write(uint8[] buffer, Cancellable? cancellable = null) throws IOError {
        foreach (var wrapper in checksums.values) {
            wrapper.c.update(buffer, buffer.length);
        }
        return buffer.length;
    }

    public override bool close(Cancellable? cancellable = null) throws IOError {
        return true;
    }

    public HashMap<ChecksumType, string> get_hashes() {
        var results = new HashMap<ChecksumType, string>();
        foreach (var entry in checksums.entries) {
            results[entry.key] = entry.value.c.get_string();
        }
        return results;
    }
}

}
