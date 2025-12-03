# Security Audit Report 2025
**Date:** December 3, 2025
**Target:** DinoX (feature/video-codecs)
**Auditor:** GitHub Copilot

## 1. Executive Summary
Following the implementation of WebRTC video calls and the previous audit, a re-evaluation of the codebase was performed.
The **WebRTC/DTLS implementation is secure**, correctly enforcing certificate verification.
However, **critical legacy issues** remain regarding private key storage and error handling.

**Overall Security Score:** **B** (Secure Network Protocol, Insecure Local Storage)

---

## 2. New Findings (WebRTC & Network)

### 2.1. ✅ DTLS Certificate Verification (Secure)
**File:** `plugins/ice/src/dtls_srtp.vala`
**Status:** **PASS**
**Analysis:**
The `verify_peer_cert` function correctly calculates the SHA-256 fingerprint of the peer's certificate and compares it against the signaled fingerprint from the XMPP channel.
*   **Algorithm:** Enforces `SHA-256`. Legacy `SHA-1` is rejected (Good for security).
*   **Logic:** Fails closed if fingerprints do not match or if multiple certificates are presented unexpectedly.
*   **MitM Protection:** Effective against Man-in-the-Middle attacks on the media stream.

### 2.2. ⚠️ ICE-TCP Enabled (Standard Risk)
**File:** `plugins/ice/src/module.vala`
**Status:** **ACCEPTABLE RISK**
**Analysis:**
We enabled `agent.ice_tcp = true` to fix mobile connectivity.
*   **Risk:** Allows the application to connect to TCP ports on remote IPs provided by the peer. Theoretically allows "port scanning" of the user's local network by a malicious peer.
*   **Mitigation:** This is standard WebRTC behavior. `libnice` handles the connection checks. No specific action required, but good to be aware of.

### 2.3. ✅ STUN/TURN Server Filtering
**File:** `plugins/ice/src/plugin.vala`
**Status:** **PASS**
**Analysis:**
The code explicitly filters out local/loopback/multicast IPs when resolving STUN/TURN servers. This prevents the application from being tricked into sending STUN packets to internal services.

---

## 3. Legacy Findings (Unresolved)

### 3.1. 🚨 CRITICAL: Unencrypted Private Keys
**File:** `plugins/omemo/src/logic/database.vala` (`IdentityTable`)
**Status:** **VULNERABLE**
**Analysis:**
OMEMO private keys are stored in the `identity_key_private_base64` column of the SQLite database `omemo.db` in **plain text**.
*   **Attack Vector:** Malware running as the user, or physical theft of the unencrypted drive.
*   **Impact:** Total compromise of past and future End-to-End Encrypted messages.
*   **Recommendation:** Use `libsecret` (Secret Service API) to store the database encryption key, and use SQLCipher or similar to encrypt the database.

### 3.2. ⚠️ HIGH: Error Swallowing (DoS Risk)
**File:** `plugins/omemo/src/plugin.vala`
**Status:** **PARTIALLY MITIGATED**
**Analysis:**
The `ensure_context()` method catches errors during OMEMO initialization and logs them, but returns `false`. The calling method `registered()` **ignores this return value**.
*   **Consequence:** If OMEMO fails to init (e.g., corrupt DB), the app continues but crashes later when `get_context()` asserts `_context != null`.
*   **Recommendation:** Handle the failure gracefully (disable the plugin, show user error) instead of crashing.

---

## 4. Recommendations

1.  **Immediate Action:** Do not deploy to production without addressing **3.1 (Key Storage)**. This is a standard requirement for secure messengers.
2.  **Refactoring:** Fix the error handling in `plugins/omemo/src/plugin.vala` to prevent crashes.
3.  **Maintenance:** Keep the strict SHA-256 enforcement in DTLS. Do not downgrade to SHA-1 for compatibility unless absolutely necessary.
