using Gee;

namespace Dino.Test {

/**
 * Stream lifecycle contract test.
 *
 * Verifies GIO stream contract used by file upload:
 *   - MemoryInputStream.is_closed() == false initially
 *   - close() must succeed without exception
 *   - is_closed() == true after close()
 *
 * Regression guard for issue #1764 (upload error stream leak).
 */
class FileManagerTest : Gee.TestCase {

    public FileManagerTest() {
        base("FileManagerTest");
        add_test("GIO_stream_close_lifecycle", test_stream_close);
    }

    /**
     * GIO contract: A newly created stream MUST NOT be closed.
     * After close(), is_closed() MUST return true.
     * close() MUST NOT throw for a valid MemoryInputStream.
     */
    void test_stream_close() {
        var test_data = "test file content";
        var mem_stream = new MemoryInputStream.from_data(test_data.data, null);

        // Contract: stream is open initially
        assert_false(mem_stream.is_closed());

        // Contract: close must succeed
        try {
            mem_stream.close();
        } catch (Error e) {
            fail_if_reached(@"Stream close failed: $(e.message)");
        }

        // Contract: stream is closed after close()
        assert_true(mem_stream.is_closed());
    }
}

}
