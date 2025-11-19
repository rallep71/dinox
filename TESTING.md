# Testing Guide for Dino Extended

## Quick Start

```bash
# Run all tests
meson test -C build

# Run specific test
meson test -C build file_manager_test

# Run with verbose output
meson test -C build --verbose
```

---

## Issue-Specific Tests

### #1764 - File Upload Segfault

**Quick Test:**
```bash
./test_issue_1764.sh
```

**What it tests:**
- File upload error handling (HTTP 413)
- Input stream cleanup
- No segmentation fault occurs

**Manual Reproduction:**
1. Start Dino: `./build/main/dino --print-xmpp=all`
2. Try to upload a file larger than server limit
3. Expected behavior:
   - ✅ Error message displayed
   - ✅ App continues running
   - ❌ NO crash/segfault

**With Valgrind (memory check):**
```bash
valgrind --leak-check=full ./build/main/dino
# Upload file, trigger error, exit Dino
# Check output for memory leaks
```

---

## Unit Tests

Located in: `libdino/tests/`

### Running Tests

```bash
# Build tests
meson test -C build

# Run with detailed output
meson test -C build --print-errorlogs

# Run specific test suite
meson test -C build --suite libdino
```

### Adding New Tests

1. Create test file in `libdino/tests/`
2. Follow pattern:
```vala
namespace Dino.Test {
    class MyTest : Gee.TestCase {
        public MyTest() {
            base("MyTest");
            add_test("test_something", test_something);
        }
        
        void test_something() {
            assert(true);
        }
    }
}
```
3. Register in `libdino/tests/meson.build`

---

## Integration Tests

### File Transfer Tests

Test file upload/download with real XMPP server:

```bash
# Setup test account in Dino
# Configure test server with known limits

# Test scenarios:
1. Upload file within limit → Success
2. Upload file over limit → Error (no crash)
3. Cancel upload mid-transfer → Clean state
4. Network error during upload → Proper cleanup
```

---

## Memory Leak Testing

### With Valgrind

```bash
# Run with memory check
valgrind \
  --leak-check=full \
  --show-leak-kinds=all \
  --track-origins=yes \
  ./build/main/dino

# Use the application
# Close Dino
# Check valgrind output for leaks
```

### With Heaptrack (Alternative)

```bash
sudo apt install heaptrack heaptrack-gui
heaptrack ./build/main/dino
# Use application
# Close and analyze: heaptrack_gui heaptrack.dino.*.zst
```

---

## Performance Testing

### Message Handling

```bash
# Test with large message history
# Monitor memory usage:
watch -n 1 'ps aux | grep dino | grep -v grep'

# Expected: Memory stays < 200MB for 7-day session
```

### Database Performance

```bash
# Test schema v30 with large dataset
sqlite3 ~/.local/share/dino/dino.db "PRAGMA integrity_check;"
sqlite3 ~/.local/share/dino/dino.db "ANALYZE;"
```

---

## Continuous Integration

Tests run automatically on:
- Every commit to master
- All pull requests
- Scheduled daily builds

See: `.github/workflows/` (when set up)

---

## Test Coverage

Current coverage targets:
- **Phase 1:** Critical paths (crash bugs)
- **Phase 5:** 90%+ for stable 1.0

Generate coverage report:
```bash
meson configure build -Db_coverage=true
meson test -C build
ninja -C build coverage-html
# Open build/meson-logs/coveragereport/index.html
```

---

## Debugging Failed Tests

```bash
# Run test under GDB
gdb --args build/main/dino
# Set breakpoints, run, debug

# Check logs
tail -f ~/.local/share/dino/dino.log

# Enable debug output
G_MESSAGES_DEBUG=all ./build/main/dino
```

---

## Reporting Test Issues

If tests fail:
1. Check `build/meson-logs/testlog.txt`
2. Run with `--verbose` flag
3. Include full output in bug report
4. Mention system: OS, GTK version, GLib version

---

**Last Updated:** November 19, 2025
