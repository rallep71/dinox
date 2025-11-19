#!/bin/bash
# Manual test script for issue #1764 - File upload segfault fix
# This script helps reproduce the bug with a test XMPP server

set -e

echo "🧪 Test for Issue #1764 - Segfault on file upload error"
echo "========================================================="
echo ""
echo "This test verifies that Dino no longer segfaults when a file"
echo "upload fails with HTTP error (e.g. 413 Payload Too Large)"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Dino is built
if [ ! -f "build/main/dino" ]; then
    echo -e "${RED}Error: Dino not built. Run: meson compile -C build${NC}"
    exit 1
fi

echo -e "${YELLOW}Test Setup Options:${NC}"
echo ""
echo "Option 1: Use local HTTP server with size limit"
echo "  - Start mock HTTP server that returns 413 for files >1MB"
echo "  - Try uploading 2MB file via Dino"
echo "  - Expected: Error message, NO segfault"
echo ""
echo "Option 2: Use real XMPP server with small limit"
echo "  - Configure your test server with 1MB file upload limit"
echo "  - Try uploading 2MB file"
echo "  - Expected: Error message, NO segfault"
echo ""
echo "Option 3: Stress test with valgrind"
echo "  - Run Dino under valgrind memory checker"
echo "  - Attempt file upload that fails"
echo "  - Expected: No memory errors reported"
echo ""

read -p "Choose option (1/2/3) or 'q' to quit: " choice

case $choice in
    1)
        echo -e "${YELLOW}Starting mock HTTP server...${NC}"
        # Create Python mock server
        cat > /tmp/test_413_server.py << 'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class TestHandler(BaseHTTPRequestHandler):
    def do_PUT(self):
        # Always return 413 Payload Too Large
        self.send_response(413)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'File too large')
        print(f"Returned 413 for PUT request")
    
    def log_message(self, format, *args):
        sys.stdout.write(f"[HTTP] {format % args}\n")

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8413), TestHandler)
    print('Mock server running on http://localhost:8413')
    print('Returns 413 for all PUT requests')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down...')
        server.shutdown()
EOF
        chmod +x /tmp/test_413_server.py
        
        echo -e "${GREEN}Mock server ready at http://localhost:8413${NC}"
        echo ""
        echo "To test:"
        echo "1. Run in another terminal: python3 /tmp/test_413_server.py"
        echo "2. Configure Dino to use http://localhost:8413 as upload endpoint"
        echo "3. Try to upload any file"
        echo "4. Verify: Error message displayed, no segfault"
        ;;
    
    2)
        echo -e "${YELLOW}Manual test with real server${NC}"
        echo ""
        echo "Steps:"
        echo "1. Ensure your XMPP server has file upload with size limit"
        echo "2. Run: ./build/main/dino --print-xmpp=all 2>&1 | tee upload_test.log"
        echo "3. Try to upload file larger than server limit"
        echo "4. Watch for error and check for segfault"
        echo ""
        echo "Expected in log:"
        echo "  ✓ 'Send file error: HTTP upload error: HTTP status code 413'"
        echo "  ✓ 'Failed to close input stream' (debug message is OK)"
        echo "  ✗ NO 'Segmentation fault' or crash"
        ;;
    
    3)
        echo -e "${YELLOW}Running valgrind memory check...${NC}"
        
        if ! command -v valgrind &> /dev/null; then
            echo -e "${RED}Error: valgrind not installed${NC}"
            echo "Install with: sudo apt install valgrind"
            exit 1
        fi
        
        echo ""
        echo "Starting Dino under valgrind..."
        echo "This will be SLOW. Try to upload a file that fails."
        echo "Press Ctrl+C when done testing."
        echo ""
        
        valgrind \
            --leak-check=full \
            --show-leak-kinds=all \
            --track-origins=yes \
            --verbose \
            --log-file=valgrind_1764.log \
            ./build/main/dino 2>&1 | tee dino_valgrind.log
        
        echo ""
        echo -e "${GREEN}Valgrind output saved to:${NC}"
        echo "  - valgrind_1764.log (memory check details)"
        echo "  - dino_valgrind.log (application output)"
        ;;
    
    q|Q)
        echo "Exiting..."
        exit 0
        ;;
    
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Test setup complete!${NC}"
echo ""
echo "To verify the fix:"
echo "  ✅ Application should display error message"
echo "  ✅ Application should continue running"
echo "  ✅ No segmentation fault should occur"
echo "  ✅ No memory leaks in valgrind (option 3)"
