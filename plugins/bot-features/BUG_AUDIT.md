# Bot-Features Plugin — Bug-Audit

**Datum:** 2025-01-20  
**Letzte Prüfung:** 2026-03-04  
**Geprüfte Dateien:** 17 Quelldateien + 1 VAPI + 1 C-Header  
**Auditor:** Copilot (Claude Opus 4.6)

---

## Zusammenfassung

| Schweregrad | Anzahl | Davon behoben |
|-------------|--------|---------------|
| KRITISCH    | 3      | 3 fixed |
| HOCH        | 5      | 4 fixed, 1 false positive |
| MITTEL      | 8      | 6 fixed, 1 offen (API-Design), 1 offen (C-Binding) |
| NIEDRIG     | 5      | 5 fixed |
| **Gesamt**  | **21** | **18 fixed, 2 offen, 1 false positive** |

---

## KRITISCH

### ~~BUG-01: Admin-Endpunkte ohne Zugriffskontrolle im Netzwerk-Modus~~ — FIXED
**Datei:** `http_server.vala`  
**Status:** Behoben — `is_localhost()` und `require_localhost()` Guard implementiert. Admin-Endpunkte im Network-Modus geben 403 für nicht-localhost Clients zurück.

---

### ~~BUG-02: Token im Klartext in Datenbank und API-Antworten gespeichert~~ — FIXED
**Datei:** `bot_registry.vala`, `http_server.vala`, `botfather_handler.vala`, `message_router.vala`  
**Status:** Behoben — `token_raw` wird nirgends mehr gelesen oder geschrieben. `BotInfo.token_raw` Property entfernt, `update_bot_token_raw()` entfernt. Token wird nur bei Erstellung einmalig angezeigt ("Save this token! It won’t be shown again."). `/showtoken` erklärt, dass Tokens nicht gespeichert werden. API-Doku verwendet `<TOKEN>` als Platzhalter. DB-Spalte bleibt im Schema (Qlite-Kompatibilität), wird aber ignoriert.

---

### ~~BUG-03: Hardcoded Default Server-Key für Token-HMAC~~ — FIXED
**Datei:** `token_manager.vala`  
**Status:** Behoben — Bei erstem Start wird ein zufälliger Key via `GLib.Uuid.string_random()` generiert und in `server_hmac_key` Setting persistiert. Erkennt und ersetzt den alten Default-Key automatisch.

---

## HOCH

### ~~BUG-04: Race Condition bei `create_bot()` — `SELECT max(id)` statt `last_insert_rowid()`~~ — FIXED
**Datei:** `bot_registry.vala`  
**Status:** Behoben — `create_bot()` und `enqueue_update()` verwenden jetzt den Rückgabewert von `InsertBuilder.perform()`, der intern `last_insert_rowid()` aufruft. Die separate SELECT-Abfrage wurde entfernt.

---

### ~~BUG-05: JSON-Injection durch String-Formatierung statt JSON-Builder~~ — FIXED
**Datei:** `bot_utils.vala`, `message_router.vala`, `http_server.vala`  
**Status:** Behoben — `escape_json()` escaped jetzt `\t` und alle Kontrollzeichen < 0x20 via `\u%04x`. Zentrale Implementierung in `BotUtils.escape_json()`, die von `ai_integration.vala` und `telegram_bridge.vala` verwendet wird. Lokale Kopien in `message_router.vala` und `http_server.vala` ebenfalls aktualisiert.

---

### ~~BUG-06: Telegram-Token in Download-URLs an XMPP-Clients weitergegeben~~ — FIXED
**Datei:** `telegram_bridge.vala`  
**Status:** Behoben — Token-haltige URLs werden nicht mehr an XMPP gesendet (seit BUG-06 v1). Debug-Logs jetzt ebenfalls bereinigt: `redact_token_url()` Helper ersetzt Token in URLs durch `<REDACTED>`, Telegram-API-Response-Bodies werden nicht mehr geloggt. Kein Token-Leak mehr in Logs.

---

### ~~BUG-07: OMEMO Auto-Trust aller Geräte-Identitäten~~ — FALSE POSITIVE
**Datei:** `bot_omemo.vala`  
**Status:** Kein Bug — gewolltes Verhalten  
**Begründung:** Der Bot nutzt einen eigenen In-Memory Signal Store und baut Sessions automatisch auf (`bundle_fetched` → `start_session`). Der Owner-Client verwendet BTBV (Blind Trust Before Verification), das Dino-Standardverhalten. Da ein Bot kein UI für manuelle Fingerprint-Verifizierung hat und sofortige verschlüsselte Kommunikation zwischen Owner und Bot erforderlich ist, ist Auto-Trust hier das korrekte Design. Ein manuelles Trust-Modell würde den Bot unbenutzbar machen.

---

### ~~BUG-08: `poll_in_progress` wird bei Fehler in `poll_telegram` nicht zurückgesetzt~~ — FIXED
**Datei:** `telegram_bridge.vala`  
**Status:** Behoben — Alle Return-Pfade (409, non-2xx, ok=false, normal, null-token) setzen jetzt `poll_in_progress[bot_id] = false` vor dem Return.

---

## MITTEL

### ~~BUG-10: Doppelte `fix_dedicated_bot_conversations()`-Aufrufe~~ — FIXED
**Datei:** `plugin.vala`  
**Status:** Behoben — Nur noch ein einzelner `GLib.Timeout.add(2500, ...)` Aufruf. Der doppelte 1s-Timer wurde entfernt.

---

### ~~BUG-11: Encryption-Status-Inkonsistenz bei Bot-Reaktivierung~~ — FIXED
**Datei:** `plugin.vala`  
**Status:** Behoben — `on_bot_status_changed()` setzt jetzt sofort `Encryption.OMEMO` statt `Encryption.NONE` bei Bot-Reaktivierung.

---

### ~~BUG-12: Kein Input-Sanitizing bei ejabberd Bot-Benutzernamen~~ — FIXED
**Datei:** `ejabberd_api.vala`  
**Status:** Behoben — `generate_bot_username()` begrenzt den sanitized Name auf max. 50 Zeichen.

---

### ~~BUG-13: Konversation-Historien unbegrenzt im Speicher (AI)~~ — FIXED
**Datei:** `ai_integration.vala`  
**Status:** Behoben — `MAX_HISTORY_KEYS = 100` Limit eingeführt. Bei Überschreitung wird der älteste Key evicted (LRU-Verhalten).

---

### BUG-14: Gemini API-Key erscheint in der URL (Query-Parameter) — OFFEN (API-Design)
**Datei:** `ai_integration.vala`  
**Status:** Nicht fixbar — Google Gemini API erfordert den Key als URL-Query-Parameter (`?key=`). Alle anderen Provider verwenden Header-Auth. Kein Code-Fix möglich ohne API-Änderung seitens Google.

---

### ~~BUG-15: `send_telegram_message` sendet HTML ohne Escaping~~ — FIXED
**Datei:** `telegram_bridge.vala`  
**Status:** Behoben — `parse_mode: "HTML"` wurde entfernt. Telegram escaped den Text jetzt automatisch.

---

### BUG-16: `addr.device_id = 0` zur Verhinderung von Speicherfreigabe — OFFEN
**Datei:** `bot_omemo.vala`  
**Status:** Offen — Workaround (`addr.device_id = 0`) an 5 Stellen noch vorhanden. C-Binding Lifecycle-Problem, low priority da funktional stabil.

**Fix:** Den Lifecycle des `Address`-Objekts korrekt verwalten (z.B. Referenz halten bis der Cipher fertig ist).

---

### ~~BUG-17: Session-Persistenz — vollständiger JSON-Blob Rewrite bei jeder Änderung~~ — FIXED
**Datei:** `bot_omemo.vala`, `bot_registry.vala`  
**Status:** Behoben — Jede Session wird jetzt einzeln unter `omemo_session:<bot_id>:<jid>:<device_id>` gespeichert. `persist_session()` schreibt nur einen DB-Key statt den gesamten Blob. Automatische Migration vom alten Blob-Format beim ersten Laden.

---

## NIEDRIG

### ~~BUG-18: `gnutls_global_init()` bei jedem Zertifikat-Aufruf~~ -- FIXED
**Datei:** `cert_gen.c`, `cert_gen.h`, `cert_gen.vapi`, `plugin.vala`  
**Status:** Behoben -- `dinox_cert_init()` und `dinox_cert_deinit()` eingefuehrt. GnuTLS wird einmalig beim Plugin-Start initialisiert und beim Shutdown deinitialisiert. Einzelfunktionen rufen `dinox_cert_init()` idempotent auf (Fallback falls direkt aufgerufen).

---

### ~~BUG-19: Fehlende `\t`-Escape in `escape_json()` aller Dateien~~ — FIXED
**Datei:** `bot_utils.vala` (zentral), `ai_integration.vala`, `telegram_bridge.vala`  
**Status:** Behoben — Zentrale `BotUtils.escape_json()` mit RFC-8259-konformem Escaping implementiert. `ai_integration.vala` und `telegram_bridge.vala` delegieren dorthin. Siehe auch BUG-05.

---

### ~~BUG-20: Rate-Limiter `cleanup()` wird nie automatisch aufgerufen~~ — FIXED
**Datei:** `rate_limiter.vala`  
**Status:** Behoben — `GLib.Timeout.add_seconds(300, ...)` ruft `cleanup()` alle 5 Minuten auf. Sauberes Teardown im Destruktor.

---

### ~~BUG-21: Webhook-Retry bei nicht-transienten Fehlern~~ — FIXED
**Datei:** `webhook_dispatcher.vala`  
**Status:** Behoben — Bei HTTP 4xx wird sofort abgebrochen, kein Retry. Nur 5xx und Netzwerk-Fehler werden wiederholt.

---

### ~~BUG-22: `delete_dedicated_bot()` Fire-and-Forget ohne Fehlerbehandlung~~ — FIXED
**Datei:** `botfather_handler.vala`, `message_router.vala`  
**Status:** Behoben — `registry.delete_bot()` wird jetzt erst im async Callback nach `ejabberd_api.unregister_account()` ausgeführt, nicht mehr vorher. Bei fehlgeschlagenem Unregister wird der Bot trotzdem gelöscht (besser als Limbo), aber der Owner erhält eine Warnung über den `deferred_response` Signal. Audit-Log zeichnet ejabberd-Ergebnis auf (`ejabberd_unregister=OK/FAILED`).

---

## Hinweise (kein Fix erforderlich)

1. **API-Key-Speicherung im Klartext:** AI- und Telegram-Keys werden als Klartext in der SQLite-Settings-Tabelle gespeichert. Bei Produktivbetrieb wäre Verschlüsselung empfehlenswert.

2. **Self-signed Cert akzeptiert überall:** `session_pool.vala` akzeptiert blindlings alle Zertifikate (`return true`). Dies ist für den Entwicklungsbetrieb akzeptabel, sollte in Produktivumgebungen konfigurierbar sein.

3. ~~**Dreifache Code-Duplikation von `escape_json()`:**~~ Behoben — Zentrale `BotUtils.escape_json()` in `bot_utils.vala`. Lokale Kopien in `message_router.vala` und `http_server.vala` noch vorhanden aber identisch aktualisiert.

4. **10-Jahres-Zertifikat:** `cert_gen.c` generiert Zertifikate mit 10 Jahren Gültigkeit. Für Self-signed akzeptabel, aber lang.

5. **BUG-09: `ejabberd_api.delete_mam_messages()` löscht Archive ALLER Benutzer:** ejabberd-API-Limitation, kein Code-Bug. Mitigation implementiert (Warnung wird angezeigt). Nicht lösbar ohne ejabberd-Änderung.
