# Issue #1766 - Memory Leak Fix

**Status**: 🔧 FIXED  
**Severity**: P0 (Critical)  
**Component**: MAM History Sync  
**Affected Version**: 0.5.0  
**Fixed In**: 0.5.0-extended (commit TBD)

---

## 🐛 Problem Description

Dino RAM usage grows from ~400MB to ~1.4GB over several hours, especially with many rooms/conversations (~100).

**Reported by**: 
- [Issue #1766](https://github.com/dino/dino/issues/1766)
- Multiple users on Debian Trixie, various Desktop Environments
- Affects commit 1742cbd and v0.5

---

## 🔍 Root Cause Analysis

### Memory Leak Location
**File**: `libdino/src/service/history_sync.vala`  
**Function**: `process_query_result()` (lines 394-450)

### The Bug

```vala
private async PageRequestResult process_query_result(...) {
    PageResult page_result = PageResult.MorePagesAvailable;

    if (query_result.malformed || query_result.error) {
        page_result = PageResult.Error;
        // ❌ BUG: stanzas[query_id] NOT cleaned up here!
    }
    
    // ... later processing ...
    
    string query_id = query_params.query_id;
    var stanzas_for_query = stanzas.has_key(query_id) ? stanzas[query_id] : null;
    
    // Cleanup only happens in send_messages_back_into_pipeline()
    // But this is NEVER called on Error path!
}
```

### Data Structure

```vala
// Line 24 in history_sync.vala
private HashMap<string, Gee.List<Xmpp.MessageStanza>> stanzas = new HashMap<string, Gee.List<Xmpp.MessageStanza>>();
```

This HashMap stores **ALL** incoming MAM (Message Archive Management) message stanzas, grouped by query ID.

### Leak Scenario

1. **User joins ~100 rooms/conversations**
2. **On each reconnect**, Dino queries MAM history for all rooms
3. **Some queries fail** (server timeout, rate limiting, errors)
   - Failed stanzas accumulate in `stanzas` HashMap
   - Never cleaned up → Memory leak
4. **Over hours/days**, RAM grows to 1.4GB+

### Why Not Caught Earlier?

- ✅ Normal path (successful MAM query) → `send_messages_back_into_pipeline()` → cleanup works
- ❌ Error path (failed MAM query) → Early return → **NO cleanup**
- Small number of rooms → Leak insignificant
- Large number of rooms (~100) → Leak becomes massive

---

## ✅ The Fix

### Code Change

**File**: `libdino/src/service/history_sync.vala`  
**Lines**: 397-406

```diff
 private async PageRequestResult process_query_result(...) {
     PageResult page_result = PageResult.MorePagesAvailable;

     if (query_result.malformed || query_result.error) {
         page_result = PageResult.Error;
+        // Clean up stanzas to prevent memory leak on query error
+        string query_id = query_params.query_id;
+        if (stanzas.has_key(query_id)) {
+            stanzas.unset(query_id);
+        }
     }
     
     // ... rest of function unchanged ...
```

### Why This Works

1. **Error Detection**: Immediately when `query_result.error` or `query_result.malformed` is true
2. **Cleanup**: Remove accumulated stanzas for that query from HashMap
3. **Early Return**: Function can safely return `PageResult.Error` without leaking memory
4. **No Side Effects**: Normal path unchanged, only error path gets cleanup

---

## 🧪 Testing

### Manual Testing

```bash
./test_issue_1766.sh
```

**Test Modes**:
1. Quick test (5 minutes)
2. Extended test (30 minutes)  
3. Stress test (2 hours)
4. Manual test (until Ctrl+C)

**Acceptance Criteria**:
- ✅ Memory < 500MB after 30 minutes
- ✅ Memory growth < 100MB over test period
- ✅ No crash/segfault
- ✅ MAM messages still loaded correctly

### Memory Profiling

```bash
# With Heaptrack (detailed analysis)
heaptrack ./build/main/dino
# Run for 30+ minutes, then quit
heaptrack_gui heaptrack.dino.*.gz

# With Valgrind (leak detection)
valgrind --leak-check=full --show-leak-kinds=all \
         --track-origins=yes \
         ./build/main/dino 2>&1 | tee valgrind_1766.log
```

### Automated Testing

```bash
# Memory benchmark
./scripts/benchmark_memory.sh --duration 1800 --rooms 100
```

---

## 📊 Expected Results

### Before Fix

| Time | Rooms | RAM Usage | Status |
|------|-------|-----------|--------|
| Startup | 100 | 400 MB | ✅ Normal |
| 1 hour | 100 | 800 MB | ⚠️ Growing |
| 4 hours | 100 | 1.4 GB | 🔴 Leak |

### After Fix

| Time | Rooms | RAM Usage | Status |
|------|-------|-----------|--------|
| Startup | 100 | 400 MB | ✅ Normal |
| 1 hour | 100 | 420 MB | ✅ Stable |
| 4 hours | 100 | 450 MB | ✅ Stable |

---

## 🔄 Related Issues

- **Similar Cleanup Pattern**: Check for other early-return paths without cleanup
  - `fetch_query()` line 342: Already has cleanup on error ✅
  - `send_messages_back_into_pipeline()` line 461: Has cleanup ✅
  
- **Future Improvements**:
  - Add RAII-style cleanup (auto-cleanup on scope exit)
  - Add memory usage metrics/telemetry
  - Consider stanza count/size limits

---

## ✅ Verification Checklist

- [x] Code review: Logic correct
- [x] Compilation: No errors/warnings
- [ ] Unit tests: Pass
- [ ] Integration tests: Pass  
- [ ] Memory profiling: No leaks
- [ ] Extended run (4+ hours): RAM stable
- [ ] Large room test (~100 rooms): RAM stable
- [ ] MAM messages load correctly
- [ ] No regressions in other features

---

## 📝 Commit Message

```
fix(mam): prevent memory leak on failed MAM queries (#1766)

Clean up stanza cache when MAM query fails due to malformed or error
response. Previously, stanzas accumulated in HashMap indefinitely,
causing RAM growth from 400MB to 1.4GB over hours with many rooms.

The bug affected users with ~100 conversations/rooms where MAM queries
occasionally fail (timeout, rate limiting, server errors). Each failed
query leaked accumulated message stanzas.

Fix adds explicit cleanup in error path before early return, matching
the cleanup behavior of the successful query path.

Fixes: #1766
Component: MAM History Sync
File: libdino/src/service/history_sync.vala
Lines: 397-406
```

---

## 🚀 Deployment

### Version
- **Target Release**: v0.6.0 (Phase 1 - Critical Stability)
- **Branch**: `fix/memory-leak-mam-1766`
- **Backport**: Consider for v0.5.1 (high priority bugfix)

### Rollout Plan
1. Merge to master after tests pass
2. Cherry-pick to stable v0.5.x branch
3. Release as v0.5.1 (hotfix) or wait for v0.6.0
4. Update DEVELOPMENT_PLAN.md

---

**Author**: @rallep71  
**Date**: November 19, 2025  
**Review Status**: Pending
