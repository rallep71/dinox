using GLib;

public class Dino.LimitInputStream : InputStream, PollableInputStream {
    private InputStream inner;
    public int64 max_bytes { public get; private set; }
    
    private int64 _retrieved_bytes = 0;
    private int64 last_update_time = 0;
    public int64 retrieved_bytes {
        get { return _retrieved_bytes; }
        private set { _retrieved_bytes = value; }
    }

    public int64 remaining_bytes { get {
        return max_bytes < 0 ? -1 : max_bytes - retrieved_bytes;
    }}

    public LimitInputStream(InputStream inner, int64 max_bytes) {
        this.inner = inner;
        this.max_bytes = max_bytes;
    }

    private void update_retrieved(ssize_t bytes) {
        _retrieved_bytes += bytes;
        
        // Throttling: Only notify every 100ms to prevent UI freeze
        int64 now = GLib.get_monotonic_time();
        if (now - last_update_time > 100 * 1000) {
            last_update_time = now;
            Idle.add(() => {
                notify_property("retrieved-bytes");
                return Source.REMOVE;
            });
        }
    }

    public bool can_poll() {
        return inner is PollableInputStream && ((PollableInputStream)inner).can_poll();
    }

    public bool is_readable() {
        if (!can_poll()) return false;
        // WORKAROUND: Force readable near end of stream to prevent hangs with TLS
        // See https://gitlab.gnome.org/GNOME/libsoup/-/issues/473
        if (remaining_bytes > 0 && remaining_bytes < 65536) return true; 
        return ((PollableInputStream)inner).is_readable();
    }

    public PollableSource create_source(Cancellable? cancellable = null) {
        if (!can_poll()) {
            return new PollableSource(this); // Fallback
        }
        return ((PollableInputStream)inner).create_source(cancellable);
    }

    public override ssize_t read(uint8[] buffer, Cancellable? cancellable = null) throws IOError {
        ssize_t read_bytes = inner.read(buffer, cancellable);
        if (read_bytes > 0) {
            update_retrieved(read_bytes);
        }
        return read_bytes;
    }

    public override async ssize_t read_async(uint8[]? buffer, int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws IOError {
        ssize_t read_bytes = yield inner.read_async(buffer, io_priority, cancellable);
        if (read_bytes > 0) {
            update_retrieved(read_bytes);
        }
        return read_bytes;
    }

    public ssize_t read_nonblocking_fn(uint8[] buffer) throws Error {
        if (!can_poll()) throw new IOError.WOULD_BLOCK("Stream is not pollable");
        ssize_t read_bytes = ((PollableInputStream)inner).read_nonblocking(buffer);
        if (read_bytes > 0) {
            update_retrieved(read_bytes);
        }
        return read_bytes;
    }
    
    public override bool close(Cancellable? cancellable = null) throws IOError {
        return inner.close(cancellable);
    }

    public override async bool close_async(int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws IOError {
        return yield inner.close_async(io_priority, cancellable);
    }
}
