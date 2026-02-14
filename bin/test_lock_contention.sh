#!/bin/bash
#
# test_lock_contention.sh - Test database lock retry behavior
#
# Usage: 
#   ./test_lock_contention.sh brief    # Hold lock for 3 seconds (should succeed)
#   ./test_lock_contention.sh stuck    # Hold lock for 10 seconds (should fail)
#

# Load config to get MUSICDB path
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$HOME/musiclib}"
if [ -f "$MUSICLIB_ROOT/config/musiclib.conf" ]; then
    source "$MUSICLIB_ROOT/config/musiclib.conf"
else
    echo "Error: Cannot load config from $MUSICLIB_ROOT/config/musiclib.conf"
    exit 1
fi

if [ -z "$MUSICDB" ]; then
    echo "Error: MUSICDB not set in config"
    exit 1
fi

LOCK_FILE="${MUSICDB}.lock"

echo "Database: $MUSICDB"
echo "Lock file: $LOCK_FILE"
echo ""

case "${1:-brief}" in
    brief)
        echo "Test: Brief lock contention (3 seconds)"
        echo "Expected: Rating should succeed after retry (~2-4 seconds total)"
        echo ""
        echo "Holding lock for 3 seconds..."
        (
            exec 200>"$LOCK_FILE"
            flock -x 200
            sleep 3
        ) &
        LOCK_PID=$!
        
        sleep 0.5  # Give lock holder time to acquire
        
        echo "Now run: time musiclib_rate.sh 3"
        echo "Press Enter when done testing, or Ctrl+C to abort"
        read
        
        # Kill lock holder if still running
        kill $LOCK_PID 2>/dev/null || true
        wait $LOCK_PID 2>/dev/null || true
        ;;
        
    stuck)
        echo "Test: Stuck lock (10 seconds)"
        echo "Expected: Rating should fail after 6 seconds with error message"
        echo ""
        echo "Holding lock for 10 seconds..."
        (
            exec 200>"$LOCK_FILE"
            flock -x 200
            sleep 10
        ) &
        LOCK_PID=$!
        
        sleep 0.5  # Give lock holder time to acquire
        
        echo "Now run: time musiclib_rate.sh 3"
        echo "Press Enter when done testing, or Ctrl+C to abort"
        read
        
        # Kill lock holder if still running
        kill $LOCK_PID 2>/dev/null || true
        wait $LOCK_PID 2>/dev/null || true
        ;;
        
    *)
        echo "Usage: $0 {brief|stuck}"
        echo ""
        echo "  brief - Test brief contention (3s lock, should succeed)"
        echo "  stuck - Test stuck lock (10s lock, should fail)"
        exit 1
        ;;
esac

echo ""
echo "Test complete. Lock released."
