using Gee;

namespace Dino.Test {

class FileManagerTest : Gee.TestCase {

    public FileManagerTest() {
        base("FileManagerTest");
        add_test("test_stream_close", test_stream_close);
    }

    /**
     * Test that MemoryInputStream can be closed without error.
     * Regression-related test for issue #1764 (upload error stream leak).
     */
    void test_stream_close() {
        var test_data = "test file content";
        var mem_stream = new MemoryInputStream.from_data(test_data.data, null);

        // Stream should be open initially
        assert_false(mem_stream.is_closed());

        // Close must succeed without crash
        try {
            mem_stream.close();
        } catch (Error e) {
            fail_if_reached(@"Stream close failed: $(e.message)");
        }

        assert_true(mem_stream.is_closed());
    }
}

}
