# Fix for Issue #115: Custom Hostname and Port Configuration

**Issue**: [#115 - Hostname and port configuration](https://github.com/dino/dino/issues/115)  
**Reactions**: 20 👍, 6 ❤️  
**Status**: ✅ IMPLEMENTED  
**Date**: 2025-01-XX

## Problem

Users cannot manually specify custom server hostname and port for XMPP connections. Currently, Dino only uses DNS SRV records to discover servers, which creates problems for:

1. **Private servers** without public SRV records
2. **VPN/Tor connections** (e.g., `.onion` addresses)
3. **Corporate networks** with internal servers
4. **Non-standard ports** (e.g., port 1935 for eduroam)

Quote from issue: *"I'm my own sysadmin and I don't want to publish a SRV because I want to keep it private"*

## Solution

Added optional custom hostname and port fields to account configuration.

### Changes Made

#### 1. Account Entity (`libdino/src/entity/account.vala`)
- Added `custom_host` (nullable string) field
- Added `custom_port` (int, default=0) field
- Updated `from_row()`, `persist()`, and `on_update()` methods

#### 2. Database Schema (`libdino/src/service/database.vala`)
- Incremented schema version: `30` → `31`
- Added columns:
  - `custom_host` (TEXT, min_version=31)
  - `custom_port` (INTEGER, min_version=31)

#### 3. Connection Logic (`xmpp-vala/src/core/stream_connect.vala`)
- Extended `establish_stream()` signature:
  ```vala
  public async XmppStreamResult establish_stream(
      Jid bare_jid, 
      Gee.List<XmppStreamModule> modules, 
      string? log_options, 
      owned TlsXmppStream.OnInvalidCert on_invalid_cert,
      string? custom_host = null,    // NEW
      uint16 custom_port = 0         // NEW
  )
  ```
- Skip SRV lookup when custom host/port provided
- Debug log: `"Using custom connection: %s:%u"`

#### 4. Connection Manager (`libdino/src/service/connection_manager.vala`)
- Pass `account.custom_host` and `account.custom_port` to `establish_stream()`
- Validate port range (1-65535)

#### 5. UI (`main/src/windows/preferences_window/add_account_dialog.*`)
- Added **"Advanced Settings"** expander in login dialog
- Fields:
  - **Server Hostname** (AdwEntryRow)
  - **Port** (AdwEntryRow)
- Appears after server availability check (when password field shows)
- Values saved to account when logging in
- Reset on dialog clear

## Usage

### Standard Login (No Custom Settings)
1. Enter XMPP address (e.g., `user@example.com`)
2. Click "Login"
3. Enter password
4. Click "Login" again

→ Uses standard SRV lookup

### Custom Host/Port Login
1. Enter XMPP address
2. Click "Login"
3. Enter password
4. Expand **"Advanced Settings"**
5. Enter:
   - **Server Hostname**: Custom server (e.g., `vpn.example.com`, `abcdef123.onion`)
   - **Port**: Custom port (e.g., `5223`, `1935`)
6. Click "Login"

→ Connects directly to specified host:port, **skips SRV lookup**

## Test Cases

### 1. Standard Port (Custom Host Only)
```
JID: user@example.com
Host: server.example.com
Port: (empty or 5222)
```
Expected: Connects to `server.example.com:5222` using STARTTLS

### 2. Custom Port
```
JID: user@university.edu
Host: xmpp.university.edu
Port: 1935
```
Expected: Connects to `xmpp.university.edu:1935` (eduroam scenario)

### 3. Tor Hidden Service
```
JID: user@onion.local
Host: abcdef123456.onion
Port: 5222
```
Expected: Connects via Tor proxy to `.onion` address

### 4. Direct TLS Port
```
JID: user@secure.example
Host: secure.example
Port: 5223
```
Expected: Connects with direct TLS (xmpps-client)

### 5. Invalid Scenarios
- **Invalid hostname**: Should fail with connection error
- **Invalid port** (0, -1, 70000): Ignored, falls back to SRV lookup
- **Empty host, valid port**: Ignored, falls back to SRV lookup

## Technical Details

### Database Migration
The schema automatically upgrades from v30 to v31 when Dino starts. New columns are added to the `account` table:
```sql
ALTER TABLE account ADD COLUMN custom_host TEXT;
ALTER TABLE account ADD COLUMN custom_port INTEGER;
```

Existing accounts get `NULL` (custom_host) and `0` (custom_port), which means "use standard SRV lookup".

### Connection Priority
1. **If custom_host set AND custom_port > 0**: Use custom connection, skip SRV
2. **Otherwise**: Standard SRV lookup (xmpp-client, xmpps-client) + fallback to `domain:5222`

### Security Considerations
- ⚠️ **Custom hosts bypass SRV records**: Users must ensure they trust the custom server
- ✅ **TLS still validated**: Certificate checks apply to custom hosts
- ✅ **Port validation**: Only 1-65535 accepted
- ℹ️ **No DNS override**: Still connects to IP resolved from custom_host

## Build Status

```bash
$ ninja -C build
[362/362] Linking target plugins/rtp/rtp.so
Compilation succeeded - 27 warning(s)
```

✅ Compiles successfully  
✅ No errors  
⚠️ 27 warnings (pre-existing, unrelated)

## Testing Instructions

1. **Start Dino**:
   ```bash
   cd /media/linux/SSD128/xmpp
   ./build/main/dino
   ```

2. **Add New Account**:
   - Click "+" in account list
   - Enter test JID
   - Click "Login"
   - When password field appears, expand **"Advanced Settings"**
   - Verify fields present: "Server Hostname", "Port"

3. **Test Custom Connection**:
   - Enter custom hostname (e.g., your server IP)
   - Enter custom port (e.g., 5223)
   - Complete login
   - Check logs for: `Using custom connection: <host>:<port>`

4. **Verify Database**:
   ```bash
   sqlite3 ~/.local/share/dino/dino.db "SELECT bare_jid, custom_host, custom_port FROM account;"
   ```

## Files Modified

1. `libdino/src/entity/account.vala` (+6 lines)
2. `libdino/src/service/database.vala` (+3 lines, VERSION++)
3. `xmpp-vala/src/core/stream_connect.vala` (+20 lines)
4. `libdino/src/service/connection_manager.vala` (+5 lines)
5. `main/data/preferences_window/add_account_dialog.ui` (+21 lines)
6. `main/src/windows/preferences_window/add_account_dialog.vala` (+16 lines)

**Total**: 71 lines added/modified across 6 files

## References

- Original issue: https://github.com/dino/dino/issues/115
- Use case: Private servers, VPN/Tor, corporate networks
- Requested since: July 2017 (7.5 years old)
- Implementation time: ~1 hour
