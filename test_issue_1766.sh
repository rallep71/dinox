#!/bin/bash
# Test Script for Issue #1766 - Memory Leak in MAM History Sync
# Tests that RAM doesn't grow excessively with multiple conversations/rooms

set -e

DINO_BIN="./build/main/dinox"
TEST_DURATION=300  # 5 minutes for quick test
MEMORY_THRESHOLD_MB=500  # Alert if RAM > 500MB

echo "🧪 Memory Leak Test for Issue #1766"
echo "===================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get memory usage in MB
get_memory_mb() {
    local pid=$1
    ps -o rss= -p "$pid" | awk '{print int($1/1024)}'
}

# Function to monitor memory over time
monitor_memory() {
    local pid=$1
    local duration=$2
    local interval=10  # Check every 10 seconds
    
    echo "📊 Monitoring memory for $duration seconds..."
    echo ""
    echo "Time(s)  | RSS(MB)  | Growth  | Status"
    echo "---------|----------|---------|--------"
    
    local initial_mem=$(get_memory_mb $pid)
    local start_time=$(date +%s)
    local max_mem=$initial_mem
    local last_mem=$initial_mem
    
    while true; do
        sleep $interval
        
        # Check if process still running
        if ! kill -0 $pid 2>/dev/null; then
            echo ""
            echo "${RED}❌ Dino crashed!${NC}"
            return 1
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $duration ]; then
            break
        fi
        
        local current_mem=$(get_memory_mb $pid)
        local growth=$((current_mem - initial_mem))
        local growth_pct=$((growth * 100 / initial_mem))
        
        if [ $current_mem -gt $max_mem ]; then
            max_mem=$current_mem
        fi
        
        # Color code based on memory status
        local status="${GREEN}✓${NC}"
        if [ $current_mem -gt $MEMORY_THRESHOLD_MB ]; then
            status="${RED}⚠${NC}"
        elif [ $growth_pct -gt 50 ]; then
            status="${YELLOW}!${NC}"
        fi
        
        printf "%8d | %8d | +%3d%% | %s\n" $elapsed $current_mem $growth_pct "$status"
        last_mem=$current_mem
    done
    
    echo ""
    echo "📈 Memory Statistics:"
    echo "  Initial:  ${initial_mem} MB"
    echo "  Final:    ${last_mem} MB"
    echo "  Maximum:  ${max_mem} MB"
    echo "  Growth:   $((last_mem - initial_mem)) MB (+$((100 * (last_mem - initial_mem) / initial_mem))%)"
    echo ""
    
    # Evaluate results
    if [ $last_mem -lt $MEMORY_THRESHOLD_MB ]; then
        echo "${GREEN}✅ PASS: Memory usage within acceptable limits${NC}"
        return 0
    elif [ $((last_mem - initial_mem)) -lt 100 ]; then
        echo "${YELLOW}⚠ WARNING: Memory high but stable${NC}"
        return 0
    else
        echo "${RED}❌ FAIL: Excessive memory growth detected${NC}"
        return 1
    fi
}

# Main test menu
echo "Select test mode:"
echo "1) Quick test (5 minutes)"
echo "2) Extended test (30 minutes)"
echo "3) Stress test (2 hours)"
echo "4) Manual test (until Ctrl+C)"
echo ""
read -p "Choice [1-4]: " choice

case $choice in
    1)
        TEST_DURATION=300
        echo "🏃 Quick Test: 5 minutes"
        ;;
    2)
        TEST_DURATION=1800
        echo "⏱️ Extended Test: 30 minutes"
        ;;
    3)
        TEST_DURATION=7200
        echo "💪 Stress Test: 2 hours"
        ;;
    4)
        TEST_DURATION=999999
        echo "🔧 Manual Test: Press Ctrl+C to stop"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "📝 Instructions:"
echo "  1. Dino will start in background"
echo "  2. Log in with your account"
echo "  3. Join multiple rooms/conversations (more = better test)"
echo "  4. Memory usage will be monitored"
echo ""
read -p "Press ENTER to start..."

# Start Dino in background
echo ""
echo "🚀 Starting Dino..."
$DINO_BIN &> /tmp/dino_test_1766.log &
DINO_PID=$!

echo "   PID: $DINO_PID"
echo "   Logs: /tmp/dino_test_1766.log"

# Wait for Dino to initialize
sleep 5

# Check if Dino started successfully
if ! kill -0 $DINO_PID 2>/dev/null; then
    echo ""
    echo "${RED}❌ Failed to start Dino!${NC}"
    echo "Check logs: tail -f /tmp/dino_test_1766.log"
    exit 1
fi

echo ""
echo "${GREEN}✅ Dino started successfully${NC}"
echo ""

# Monitor memory
if monitor_memory $DINO_PID $TEST_DURATION; then
    TEST_RESULT=0
else
    TEST_RESULT=1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up..."
if kill -0 $DINO_PID 2>/dev/null; then
    kill $DINO_PID
    sleep 2
    if kill -0 $DINO_PID 2>/dev/null; then
        kill -9 $DINO_PID
    fi
fi

echo ""
echo "📋 Test completed!"
echo "Logs saved to: /tmp/dino_test_1766.log"

exit $TEST_RESULT
