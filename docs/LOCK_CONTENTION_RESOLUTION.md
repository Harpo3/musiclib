# Database Lock Contention - Revised Error Handling

## Problem Statement

**Scenario**: User presses META+3 to rate a track at the exact moment `musiclib_audacious.sh` is updating the database (song change event). The rating script attempts to acquire the database lock but times out after 5 seconds.

**Current Behavior** (per normalization):
```json
{
  "error": "Database lock timeout - another process may be using the database",
  "script": "musiclib_rate.sh",
  "code": 2,
  "context": {"timeout": "5 seconds"},
  "timestamp": "2025-02-04T18:45:23Z"
}
```
Exit code 2, user sees error notification, rating is lost.

**Problem**: This is a poor user experience. The user's intent (rate this track) is valid and should succeed, not fail with a cryptic timeout error.

---

## Proposed Solution: Deferred Rating with User Feedback

### Approach

When `musiclib_rate.sh` encounters a database lock timeout:
1. **Cache the rating request** to a pending operations file
2. **Show immediate user feedback** that rating is pending
3. **Retry automatically** when lock becomes available
4. **Confirm completion** with final notification

### Implementation Details

#### 1. Pending Operations File

**Location**: `$MUSICLIB_ROOT/data/.pending_operations`

**Format**: One operation per line, pipe-delimited
```
timestamp|script|operation|args
1738694345|musiclib_rate.sh|rate|/path/to/song.mp3|3
1738694346|musiclib_rate.sh|rate|/path/to/other.mp3|5
```

**Fields**:
- `timestamp`: Unix epoch when operation was queued
- `script`: Script name that queued the operation
- `operation`: Operation type (e.g., "rate", "update_lastplayed", "set_genre")
- `args`: Operation-specific arguments (pipe-delimited)

#### 2. Modified musiclib_rate.sh Logic

```bash
# After lock timeout (exit code 1 from with_db_lock)
if [ "$lock_result" -eq 1 ]; then
    # Queue the rating operation
    PENDING_FILE="$MUSICLIB_ROOT/data/.pending_operations"
    TIMESTAMP=$(date +%s)
    echo "$TIMESTAMP|musiclib_rate.sh|rate|$FILEPATH|$STAR_RATING" >> "$PENDING_FILE"
    
    # Show user feedback - rating is pending
    if command -v kdialog >/dev/null 2>&1; then
        track_title=$(audtool --current-song-tuple-data title 2>/dev/null || basename "$FILEPATH")
        star_display=$(printf '★%.0s' $(seq 1 $STAR_RATING))
        kdialog --title 'Rating Queued' --passivepopup \
            "Rating $star_display for \"$track_title\" is pending database access..." 5 &
    fi
    
    # Log with special marker for pending operation
    log_message "PENDING: Rating $FILEPATH -> $STAR_RATING stars (database locked)"
    
    # Exit with special code 3 = "operation queued"
    exit 3
fi
```

#### 3. Pending Operations Processor

**New Script**: `musiclib_process_pending.sh`

This script:
- Runs automatically after database-writing operations complete
- Can also be invoked manually or on a timer
- Processes all pending operations in FIFO order
- Removes successfully completed operations from queue

```bash
#!/bin/bash
# musiclib_process_pending.sh - Process queued database operations

PENDING_FILE="$MUSICLIB_ROOT/data/.pending_operations"
LOCK_FILE="$MUSICLIB_ROOT/data/.pending_operations.lock"

# Don't run if no pending operations
if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
    exit 0
fi

# Acquire lock on pending file (prevent concurrent processing)
exec {LOCK_FD}>"$LOCK_FILE"
if ! flock -n "$LOCK_FD"; then
    # Another processor is already running
    exit 0
fi

# Process each pending operation
while IFS='|' read -r timestamp script operation args; do
    case "$operation" in
        rate)
            # Extract filepath and star_rating from args
            filepath=$(echo "$args" | cut -d'|' -f1)
            star_rating=$(echo "$args" | cut -d'|' -f2)
            
            # Attempt to execute the rating (internal function, not full script)
            if update_rating_in_db "$filepath" "$star_rating"; then
                log_message "COMPLETED PENDING: Rated $filepath -> $star_rating stars"
                
                # Show completion notification
                if command -v kdialog >/dev/null 2>&1; then
                    track_title=$(basename "$filepath")
                    star_display=$(printf '★%.0s' $(seq 1 $star_rating))
                    kdialog --title 'Rating Applied' --passivepopup \
                        "Rating $star_display applied to \"$track_title\"" 3 &
                fi
                
                # Remove this line from pending file
                sed -i "/^$timestamp|/d" "$PENDING_FILE"
            else
                # Failed again - leave in queue, will retry later
                log_message "RETRY FAILED: Cannot rate $filepath (will retry)"
            fi
            ;;
        *)
            log_message "UNKNOWN PENDING OPERATION: $operation"
            # Remove unknown operations
            sed -i "/^$timestamp|/d" "$PENDING_FILE"
            ;;
    esac
done < "$PENDING_FILE"

# Release lock
flock -u "$LOCK_FD"
exec {LOCK_FD}>&-

exit 0
```

#### 4. Integration Points

**A. Call from musiclib_audacious.sh**
After database update completes, process pending operations:
```bash
# At end of musiclib_audacious.sh, after database updates
if [ -f "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" ]; then
    "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" &
fi
```

**B. Call from musiclib_rate.sh**
After successfully acquiring lock and updating, also process any other pending operations:
```bash
# After successful database update in musiclib_rate.sh
if [ -f "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" ]; then
    "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" &
fi
```

**C. Periodic Timer (Optional)**
Add a systemd timer or cron job:
```bash
# Every 30 seconds, process pending operations
*/1 * * * * /home/user/musiclib/bin/musiclib_process_pending.sh >/dev/null 2>&1
```

---

## Exit Code Extension

### New Exit Code 3: Operation Queued

**When**: Database lock could not be acquired, but operation was successfully queued for later processing

**Semantics**:
- Not an error - user intent was preserved
- Operation will complete asynchronously
- User should be notified that completion is pending

**Updated Exit Code Contract**:
- **0**: Success (operation completed immediately)
- **1**: User error (invalid input, precondition not met)
- **2**: System error (unrecoverable failure)
- **3**: Deferred success (operation queued, will complete later)

---

## BACKEND_API.md Updates

### Section 1.1 - Exit Codes (Revised)

```markdown
### 1.1 Exit Codes

All scripts conform to the following exit code contract:

| Code | Meaning | Semantics | User Action |
|------|---------|-----------|-------------|
| 0 | Success | Operation completed immediately | None |
| 1 | User Error | Invalid input, precondition not met | Fix input and retry |
| 2 | System Error | Unrecoverable failure (missing tool, I/O error) | Check logs, fix environment |
| 3 | Deferred Success | Operation queued due to database contention | Wait for completion notification |

**Exit Code 3 Details**:
- Returned when database lock cannot be acquired within timeout
- Operation is queued in `$MUSICLIB_ROOT/data/.pending_operations`
- Operation will be retried automatically when lock becomes available
- User receives "pending" notification immediately and "completed" notification later
- Scripts that support exit code 3: musiclib_rate.sh, musiclib_mobile.sh (any DB-writing script)
```

### Section 2.2 - musiclib_rate.sh (Add to Error Cases)

```markdown
**Error Cases**:
| Exit | Condition | Context Fields | User Experience |
|------|-----------|----------------|-----------------|
| ... existing errors ... |
| 3 | Database lock timeout (queued) | `timeout`, `filepath`, `stars` | "Rating queued" notification, followed by "Rating applied" when complete |
```

### New Section 2.8 - musiclib_process_pending.sh

```markdown
### 2.8 musiclib_process_pending.sh
**Purpose**: Process queued database operations after lock contention

**Usage**:
```bash
musiclib_process_pending.sh
```

**Invocation**:
- Called automatically at end of database-writing scripts
- Can be called manually to force processing
- Can be run on a timer (cron/systemd) for reliability

**Preconditions**:
- Pending operations file exists: `$MUSICLIB_ROOT/data/.pending_operations`
- Database lock is available

**Side Effects**:
- Processes all pending operations in FIFO order
- Updates database for each successfully completed operation
- Shows completion notifications for user-facing operations
- Removes completed operations from pending file
- Logs all processed operations

**Exit Codes**:
| Exit | Condition |
|------|-----------|
| 0 | Success (all operations processed or no operations pending) |
| 2 | System error (cannot access pending file) |

**Notes**:
- Uses its own lock file (`.pending_operations.lock`) to prevent concurrent processing
- Non-blocking: if another processor is running, exits immediately
- Safe to call multiple times concurrently
- Does not emit JSON errors (internal automation script)
```

---

## User Experience Flow

### Happy Path (No Contention)
1. User presses META+3
2. `musiclib_rate.sh` acquires lock immediately
3. Database updated
4. User sees "★★★ rated" notification
5. Exit code 0

### Lock Contention Path
1. User presses META+3
2. `musiclib_rate.sh` cannot acquire lock (audacious.sh is writing)
3. Operation queued to `.pending_operations`
4. User sees "Rating ★★★ is pending database access..." notification (5 seconds)
5. Exit code 3
6. 2-3 seconds later: audacious.sh finishes, calls `process_pending.sh`
7. `process_pending.sh` completes the rating
8. User sees "Rating ★★★ applied to [track]" notification (3 seconds)

### Total User Perception
- **No contention**: Instant feedback (< 1 second)
- **With contention**: Deferred feedback (2-8 seconds), but user knows what's happening

---

## Migration from Normalized Version

The currently normalized `musiclib_rate.sh` needs these additions:

1. Add exit code 3 logic for lock timeout
2. Add pending operation queueing
3. Add "rating queued" notification
4. Call `musiclib_process_pending.sh` after successful updates

This is **backward compatible**:
- Old behavior: exit 2 on lock timeout (error)
- New behavior: exit 3 on lock timeout (queued for later)
- No changes needed for exit 0 (immediate success) path

---

## Testing Scenarios

### Test 1: Simulate Lock Contention
```bash
# Terminal 1: Hold lock for 10 seconds
(flock -x 200; sleep 10) 200>/tmp/musiclib.dsv.lock &

# Terminal 2: Attempt rating (should queue)
./musiclib_rate.sh 3
# Should show "Rating queued" notification
# Should exit with code 3
# Should create entry in .pending_operations

# After 10 seconds, process pending
./musiclib_process_pending.sh
# Should show "Rating applied" notification
# Should remove entry from .pending_operations
```

### Test 2: Rapid Rating Changes
```bash
# Rate track multiple times rapidly
./musiclib_rate.sh 3 &
./musiclib_rate.sh 4 &
./musiclib_rate.sh 5 &

# All should succeed (either immediately or queued)
# Final rating should be 5 stars (last write wins)
```

### Test 3: Concurrent Song Changes and Ratings
```bash
# Have Audacious playing and changing songs
# Rapidly press META+3, META+4, META+5 during song changes
# All ratings should eventually complete
# No database corruption should occur
```

---

## Questions for Discussion

1. **Timeout value**: Should the 5-second timeout be reduced since we now have queueing? Maybe 1-2 seconds?

2. **Queue persistence**: Should `.pending_operations` survive reboots? Currently it's just a regular file.

3. **Queue expiration**: Should old pending operations (> 5 minutes) be discarded?

4. **Notification verbosity**: Two notifications per queued operation might be annoying. Should we suppress the "completed" notification if it happens within 3 seconds of "queued"?

5. **GUI integration**: Should the GUI show a persistent indicator when pending operations exist?

6. **Error escalation**: If a pending operation fails 3 times, should it be moved to a "failed" queue and alert the user?
