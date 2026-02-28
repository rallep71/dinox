# OMEMO Plugin — Bug Audit Report

**Datum:** 2025-01-XX  
**Scope:** 39 Quelldateien, ~7785 Zeilen  
**Methode:** Manuelles Code-Review aller Dateien, False-Positive-Analyse

---

## Gefundene Bugs: 2 (beide LOW)

### BUG-01 — `delete_all_sessions()` modifiziert Liste während Iteration
- **Datei:** `plugins/omemo/src/native/simple_ss.vala`, Zeile 63–70
- **Schwere:** LOW
- **CWE:** CWE-662 (Improper Synchronization → concurrent modification)

**Problem:**
`delete_all_sessions()` iteriert über `session_map[name]` (ein `ArrayList`) und ruft
innerhalb der `foreach`-Schleife `session_map[name].remove(session)` auf. In Gee.ArrayList
verschiebt `remove()` nachfolgende Elemente nach links. Der Iterator merkt das nicht und
springt zum nächsten Index — dadurch wird das Element, das an die Stelle des gelöschten
gerutscht ist, übersprungen.

**Beispiel:**
Bei 2 Sessions (A, B) in der Liste:
1. Index 0 → Session A entfernt, B rutscht auf Index 0
2. Iterator springt auf Index 1 → Liste hat nur noch 1 Element → Schleife endet
3. Session B wurde **nie entfernt**

**Impact:**
Wenn das Signal-Protocol `delete_all_sessions` aufruft (z.B. bei Kontakt-Cleanup),
bleiben einige Sessions im In-Memory-Store + Datenbank erhalten. Die nicht gelöschten
Sessions werden auch nicht per `session_removed`-Signal an die Datenbank gemeldet.

**Fix:**
Liste kopieren oder rückwärts iterieren.

---

### BUG-02 — `own_notifications` wird bei Multi-Account überschrieben
- **Datei:** `plugins/omemo/src/plugin.vala`, Zeile 37 + 79
- **Schwere:** LOW (kosmetisch)
- **CWE:** CWE-463 (Deletion of Data Structure Sentinel) — Referenzverlust

**Problem:**
Im `initialize_account_modules`-Handler wird `this.own_notifications` bei jedem Account
neu zugewiesen:
```vala
this.own_notifications = new OwnNotifications(this, this.app.stream_interactor, account);
```
Bei mehreren Accounts zeigt das Feld nur auf den zuletzt initialisierten Account.

**Impact:**
Minimal — die überschriebenen OwnNotifications-Objekte bleiben durch ihre Signal-
Handler am Leben und funktionieren weiter. Das Feld selbst ist aber unbrauchbar für
Multi-Account-Zugriff.

**Fix:**
`HashMap<Account, OwnNotifications>` statt einzelnem Feld verwenden.

---

## False Positives (analysiert und verworfen): 17

| # | Verdacht | Analyse | Ergebnis |
|---|----------|---------|----------|
| 1 | `get_trusted_devices` akzeptiert UNKNOWN-Devices mit `identity_key==null` | Design: Phantom-Placeholder-Devices werden eingeschlossen, damit der Retry-Mechanismus Bundle-Fetch auslöst. Encryption scheitert graceful. | FALSE POSITIVE |
| 2 | v2 `encrypt_key` setzt `cipher.version=4` auf möglicherweise v3-Session | v2 verschlüsselt nur zu Devices auf der v2-Device-List (die v4 unterstützen). Ratchet-State ist versionsunabhängig. | FALSE POSITIVE |
| 3 | Identity-Key-Änderung wird in `update_db_for_prekey` still akzeptiert | Bereits als Bug #19 im Code dokumentiert. Design-Entscheidung (TOFU). | FALSE POSITIVE (bekannt) |
| 4 | `session_repair_attempted` ist nur per-Runtime (HashSet, nicht persistiert) | By Design: Nach Neustart sollen Sessions erneut repariert werden. Per-Runtime reicht gegen Thrashing. | FALSE POSITIVE |
| 5 | `arr_to_str` erstellt Array+1 für Null-Terminierung | Korrektes Pattern für Vala → C-String-Konversion. | FALSE POSITIVE |
| 6 | `address.device_id = 0` Hack in mehreren Dateien | Dokumentierter Workaround für Vala-Reference-Counting mit C-Interop (hält Address am Leben). | FALSE POSITIVE |
| 7 | `encrypt_key_to_recipients` bricht bei erstem unbekannten Empfänger ab | `other_waiting_lists` wird inkrementiert, `return` folgt sofort. Korrekte Early-Return-Logik. | FALSE POSITIVE |
| 8 | `jet_omemo` `generate_random_secret` warnt nur bei Randomize-Fehler | OS-CSPRNG-Fehler ist katastrophal und praktisch unmöglich. Warning-only ist akzeptabel. | FALSE POSITIVE |
| 9 | v1 `DecryptMessageListener` prüft nicht `has_key` (v2 schon) | Decryptors werden VOR dem Listener initialisiert. Theoretische Race-Condition, praktisch unmöglich. | FALSE POSITIVE |
| 10 | `IGNORE_TIME = TimeSpan.MINUTE` — zu kurz für Device-Ignore? | By Design: Temporäres Ignore nur für Bundle-Fetch-Zyklen. Devices werden nicht permanent ignoriert. | FALSE POSITIVE |
| 11 | `start_session` in `stream_module_v2.vala` prüft nicht v3→v4 Upgrade | v1-Module macht v4→v3 (Downgrade), v2-Module überspringt existierende Sessions. Sessions werden separat gehandhabt. | FALSE POSITIVE |
| 12 | `MessageFlag` verwendet Legacy-Namespace `NS_URI` | Flag ist nur ein Marker gegen Doppel-Verarbeitung. Der Namespace ist irrelevant für die Funktion. | FALSE POSITIVE |
| 13 | `normalize_base64` gibt Leerstring bei `length ≡ 1 mod 4` zurück | RFC 4648: length ≡ 1 (mod 4) ist immer ungültiges Base64. Korrekte Behandlung. | FALSE POSITIVE |
| 14 | `key` wird in `encrypt_plaintext` nach Copy in `keytag` gezeroized | Korrekte Sicherheitsmaßnahme. `keytag` enthält den Key weiterhin (nötig für Verschlüsselung). | FALSE POSITIVE |
| 15 | `omemo2_encrypt_payload` zeroized `hkdf_output/enc_key/auth_key` | Intermediäre Schlüssel werden nach Gebrauch gelöscht. `mk_with_tag` enthält `mk` absichtlich (wird an Empfänger geschickt). | FALSE POSITIVE |
| 16 | `set_device_trust` baut Raw-SQL WHERE-Clause zusammen | Werte kommen von Integer-IDs (`.to_string()`), keine SQL-Injection möglich. Standard-Qlite-Pattern. | FALSE POSITIVE |
| 17 | `constant_time_compare` in `simple_iks.vala` und `decrypt_v2.vala` | Beide Implementierungen verwenden `result |= a[i] ^ b[i]` — korrektes Constant-Time-Pattern. | FALSE POSITIVE |

---

## Architektur-Notizen (keine Bugs, aber erwähnt)

1. **Dual v1/v2 Unterstützung** — Sauber getrennt in parallelen Klassen
   (OmemoEncryptor/Omemo2Encrypt, OmemoDecryptor/Omemo2Decrypt). Keine Vermischung.

2. **Kryptografie** — HKDF→AES-256-CBC→HMAC Pipeline in v2 ist korrekt implementiert.
   HMAC-Verifikation vor Entschlüsselung (Encrypt-then-MAC). Constant-Time-Vergleich.

3. **Key-Zeroization** — AES-Keys, HKDF-Output und intermediäre Schlüssel werden
   nach Gebrauch gezeroized. Vala/GLib bietet keine garantierte Zeroization (Compiler
   könnte optimieren), aber `Memory.set(key, 0, len)` ist der Best-Effort-Ansatz.

4. **Datenbank-Verschlüsselung** — OMEMO-DB verwendet separaten Key aus GNOME Keyring
   (`KeyManager.get_or_create_db_key()`). `PRAGMA secure_delete = ON` aktiv.

5. **Session-Repair** — One-Shot-Repair bei `SG_ERR_NO_SESSION`/`SG_ERR_INVALID_MESSAGE`
   mit per-Runtime Tracking gegen Thrashing. Gut durchdacht.

6. **ESFS-Unterstützung** — `file_decryptor.vala` handhabt sowohl Legacy `aesgcm://`
   als auch XEP-0448 ESFS mit CBC/GCM-Fallback für Kaidan-Interop.

---

## Fazit

Das OMEMO-Plugin ist insgesamt **sehr solide** implementiert. Die Kryptografie-Pipeline
ist korrekt, Key-Management ist durchdacht, und die Signal-Protocol-Integration ist
sauber. Die beiden gefundenen Bugs sind beide LOW-Severity und betreffen Edge-Cases
(Bulk-Session-Delete und Multi-Account-Feld).
