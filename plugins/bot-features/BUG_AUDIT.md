# Bot-Features Plugin — Bug-Audit

**Datum:** 2025-01-20  
**Geprüfte Dateien:** 17 Quelldateien + 1 VAPI + 1 C-Header  
**Auditor:** Copilot (Claude Opus 4.6)

---

## Zusammenfassung

| Schweregrad | Anzahl |
|-------------|--------|
| KRITISCH    | 3      |
| HOCH        | 6      |
| MITTEL      | 8      |
| NIEDRIG     | 5      |
| **Gesamt**  | **22** |

---

## KRITISCH

### BUG-01: Admin-Endpunkte ohne Zugriffskontrolle im Netzwerk-Modus
**Datei:** `http_server.vala`, Zeilen 48–53, 68–69  
**Beschreibung:** Die Management-Endpunkte (`/bot/create`, `/bot/list`, `/bot/delete`, `/bot/activate`, `/bot/token`, `/bot/revoke`) sind als "localhost only" dokumentiert (Zeile 125 Kommentar), aber es gibt **keine tatsächliche Prüfung** auf `127.0.0.1` oder `::1`. Im `network`-Modus lauscht der Server auf `0.0.0.0` (alle Interfaces), und **jeder Netzwerk-Client** kann ohne Authentifizierung Bots erstellen, löschen, Tokens generieren und widerrufen.

**Auswirkung:** Vollständige Remote-Übernahme der Bot-Infrastruktur durch jeden Netzwerk-Teilnehmer.

**Fix:**
```vala
// In jeder handle_*_bot-Methode am Anfang prüfen:
private bool is_localhost(Soup.ServerMessage msg) {
    var remote = msg.get_remote_host();
    return remote == "127.0.0.1" || remote == "::1" || remote == "localhost";
}

// Dann:
if (current_mode == "network" && !is_localhost(msg)) {
    AuthMiddleware.send_error(msg, 403, "forbidden", "Admin endpoints are localhost-only");
    return;
}
```

---

### BUG-02: Token im Klartext in Datenbank und API-Antworten gespeichert
**Datei:** `bot_registry.vala`, Zeile 23; `http_server.vala`, Zeilen 1248–1249  
**Beschreibung:**  
1. Das `token_raw`-Feld speichert den API-Token im Klartext in SQLite (neben dem HMAC-Hash).  
2. `bot_to_json()` in `http_server.vala` gibt `token_raw` in der JSON-Antwort von `/bot/list` an **jeden unauthentifizierten Aufrufer** zurück.  
3. In `message_router.vala` werden Token in `/api auth`-Menüs und Beispielen an den Bot-Owner gezeigt — das ist beabsichtigt, aber die DB-Speicherung im Klartext macht eine DB-Kompromittierung zu einer vollständigen Token-Kompromittierung.

**Auswirkung:** Wenn die SQLite-DB ausgelesen wird, sind alle Bot-Tokens sofort nutzbar. Zusammen mit BUG-01 kann jeder Netzwerk-Teilnehmer per `/bot/list` alle Tokens abfragen.

**Fix:**  
- `token_raw` nur bei der Erstellung **einmalig** zurückgeben, dann aus der DB löschen  
- Oder: Tokens verschlüsselt speichern (z.B. mit dem Server-Key)  
- `/bot/list` sollte `token_raw` **nie** enthalten

---

### BUG-03: Hardcoded Default Server-Key für Token-HMAC
**Datei:** `token_manager.vala`, Zeile 10  
**Beschreibung:** Der HMAC-Key für Token-Hashing ist hardcoded als `"dinox-default-server-key"`. Wenn der Benutzer keinen eigenen Key konfiguriert, können Angreifer mit Kenntnis des Quellcodes gültige Token-Hashes berechnen und so die Token-Validierung umgehen (wenn sie den Token-Text erraten oder brute-forcen können).

**Auswirkung:** Schwache kryptographische Absicherung der Token-Hashes. Der HMAC bietet keinen Schutz über einen einfachen Hash hinaus, wenn der Key öffentlich bekannt ist.

**Fix:**
```vala
// Beim ersten Start einen zufälligen Key generieren und in Settings speichern:
string? key = registry.get_setting("server_hmac_key");
if (key == null || key == "dinox-default-server-key") {
    key = GLib.Uuid.string_random() + GLib.Uuid.string_random();
    registry.set_setting("server_hmac_key", key);
}
this.server_key = key;
```

---

## HOCH

### BUG-04: Race Condition bei `create_bot()` — `SELECT max(id)` statt `last_insert_rowid()`
**Datei:** `bot_registry.vala`, Zeilen 141–144  
**Beschreibung:** Die Methode `create_bot()` ermittelt die neue Bot-ID mit:
```vala
foreach (Qlite.Row row in bot.select({bot.id}).order_by(bot.id, "DESC").limit(1)) {
    result_id = bot.id.get(row);
}
```
Bei gleichzeitigen Aufrufen (z.B. zwei API-Requests parallel) kann ein anderer INSERT zwischen dem INSERT und dem SELECT stattfinden, was dazu führt, dass die falsche ID zurückgegeben wird.

**Auswirkung:** Der falsche Bot erhält den generierten Token, der echte Bot bleibt ohne Token.

**Fix:** `last_insert_rowid()` von SQLite verwenden, oder eine Transaktion verwenden.

---

### BUG-05: JSON-Injection durch String-Formatierung statt JSON-Builder
**Datei:** `message_router.vala`, Zeilen 319–323; `http_server.vala`, Zeilen 191, 225, 1241–1256  
**Beschreibung:** JSON-Payloads werden mit `string.printf()` und einer einfachen `escape_json()`-Funktion gebaut:
```vala
string payload = "{\"from\":\"%s\",\"to\":\"%s\",\"body\":\"%s\",...}".printf(
    escape_json(from_str), escape_json(to_str), escape_json(stanza.body ?? ""), ...);
```
Die `escape_json()`-Funktion (Zeile 1759) escaped nur `\`, `"`, `\n`, `\r` — aber **nicht** Kontrollzeichen wie `\t`, `\b`, `\f`, `\0`, oder Unicode-Steuerzeichen (U+0000–U+001F), die laut RFC 8259 escapt werden müssen.

**Auswirkung:** Speziell gestaltete XMPP-Nachrichten mit Kontrollzeichen können ungültiges JSON erzeugen oder JSON-Parsing bei Webhook-Empfängern stören.

**Fix:**
```vala
private static string escape_json(string s) {
    var sb = new StringBuilder();
    for (int i = 0; i < s.length; i++) {
        unichar c = s[i];
        if (c == '\\') sb.append("\\\\");
        else if (c == '"') sb.append("\\\"");
        else if (c == '\n') sb.append("\\n");
        else if (c == '\r') sb.append("\\r");
        else if (c == '\t') sb.append("\\t");
        else if (c < 0x20) sb.append("\\u%04x".printf(c));
        else sb.append_unichar(c);
    }
    return sb.str;
}
```
Oder besser: `Json.Builder` überall verwenden (wie in `bot_omemo.vala` bereits getan).

---

### BUG-06: Telegram-Token in Download-URLs an XMPP-Clients weitergegeben
**Datei:** `telegram_bridge.vala`, Zeile 539 (in `resolve_telegram_file`)  
**Beschreibung:** Bei Telegram-Medien wird die Download-URL `https://api.telegram.org/file/bot<TOKEN>/<path>` direkt an XMPP gesendet. Diese URL enthält den vollständigen **Telegram-Bot-Token** im Klartext und wird im XMPP-Chat-Verlauf gespeichert.

**Auswirkung:** Jeder, der die XMPP-Nachricht liest (MAM-Archiv, Server-Admin, andere XMPP-Clients), kann den Telegram-Bot-Token extrahieren und den Telegram-Bot übernehmen.

**Fix:** Dateien lokal herunterladen und über den eigenen HTTP-Server oder XMPP HTTP-Upload weiterleiten, ohne den Token zu exponieren.

---

### ~~BUG-07: OMEMO Auto-Trust aller Geräte-Identitäten~~ — FALSE POSITIVE
**Datei:** `bot_omemo.vala`  
**Status:** ❌ Kein Bug — gewolltes Verhalten  
**Begründung:** Der Bot nutzt einen eigenen In-Memory Signal Store und baut Sessions automatisch auf (`bundle_fetched` → `start_session`). Der Owner-Client verwendet BTBV (Blind Trust Before Verification), das Dino-Standardverhalten. Da ein Bot kein UI für manuelle Fingerprint-Verifizierung hat und sofortige verschlüsselte Kommunikation zwischen Owner und Bot erforderlich ist, ist Auto-Trust hier das korrekte Design. Ein manuelles Trust-Modell würde den Bot unbenutzbar machen.

---

### BUG-08: `poll_in_progress` wird bei Fehler in `poll_telegram` nicht zurückgesetzt
**Datei:** `telegram_bridge.vala`, Zeile 369  
**Beschreibung:** Im `poll_telegram()`-Catch-Block wird `poll_in_progress[bot_id] = false;` korrekt am Ende gesetzt (Zeile 530). Aber wenn `root.get_boolean_member("ok")` eine Exception wirft (z.B. fehlendes "ok"-Feld, oder `root` ist null), wird der Catch-Block **nicht** erreicht (es wird vor dem try/catch geworfen), und `poll_in_progress` bleibt auf `true`. 

Genauer: Wenn `get_boolean_member("ok")` eine Exception wirft, wird sie vom Catch gefangen. Aber die `return;` in Zeile 387 (`if (!root.get_boolean_member("ok")) return;`) beendet die Methode **ohne** `poll_in_progress[bot_id] = false` — ein "ok":false-Ergebnis blockiert das Polling permanent.

**Auswirkung:** Polling für diesen Bot wird dauerhaft blockiert, bis der Bot neu gestartet wird.

**Fix:** `poll_in_progress[bot_id] = false;` in einen `finally`-Block verschieben oder vor jedem `return` setzen.

---

### BUG-09: `ejabberd_api.delete_mam_messages()` löscht Archive ALLER Benutzer
**Datei:** `ejabberd_api.vala` (WARNING-Kommentar bereits vorhanden); `message_router.vala`, Zeilen 907–916  
**Beschreibung:** Der `/clear mam`-Befehl ruft `delete_mam_messages()` auf, das die ejabberd-REST-API `delete_old_mam_messages` aufruft. Diese löscht das MAM-Archiv **aller Benutzer auf dem Server**, nicht nur des aktuellen Bots. Der Benutzer muss zwar explizit "mam" als Scope angeben, aber die Auswirkung ist nicht klar genug kommuniziert.

**Auswirkung:** Datenverlust für alle Server-Benutzer bei unbeabsichtigter Nutzung.

**Fix:** Deutlichere Bestätigungsmeldung vor der Ausführung, oder die Funktion ganz entfernen/deaktivieren, bis ejabberd eine per-User MAM-Löschung unterstützt.

---

## MITTEL

### BUG-10: Doppelte `fix_dedicated_bot_conversations()`-Aufrufe
**Datei:** `plugin.vala` (Zeilen ~430–440 und ~460–470 aus dem Summary)  
**Beschreibung:** `fix_dedicated_bot_conversations()` wird über `GLib.Timeout.add()` mit 1 Sekunde und nochmal mit 2.5 Sekunden Verzögerung aufgerufen. Beide Timer laufen parallel und die Methode wird zweimal hintereinander ausgeführt, was unnötige DB-Abfragen und Conversation-Öffnungen verursacht.

**Auswirkung:** Unkritisch, aber verschwendet Ressourcen und kann zu Race Conditions beim Öffnen von Conversations führen.

**Fix:** Nur einen Timer verwenden (z.B. 2 Sekunden) oder den zweiten Timer nur starten, wenn der erste fehlschlägt.

---

### BUG-11: Encryption-Status-Inkonsistenz bei Bot-Reaktivierung
**Datei:** `plugin.vala`  
**Beschreibung:** `on_bot_status_changed()` setzt bei der Reaktivierung eines dedizierten Bots `Encryption.NONE`, aber `on_dedicated_bot_ready()` (nach der Stream-Verbindung) setzt `Encryption.OMEMO`. Das führt zu einem kurzen Zeitfenster, in dem Nachrichten unverschlüsselt gesendet werden könnten.

**Auswirkung:** Nachrichten im Zeitfenster zwischen Reaktivierung und Stream-Ready werden ggf. unverschlüsselt gesendet.

**Fix:** `Encryption.NONE` nicht bei Reaktivierung setzen, oder sofort `Encryption.OMEMO` setzen und auf den Stream warten.

---

### BUG-12: Kein Input-Sanitizing bei ejabberd Bot-Benutzernamen
**Datei:** `ejabberd_api.vala`  
**Beschreibung:** Der Bot-Username wird durch einfaches Ersetzen von Nicht-Alphanumerischen Zeichen generiert: `bot_<sanitized_name>_<4hex>`. Aber der `sanitized_name` wird nur mit `[^a-z0-9_]` gefiltert. Bei sehr langen Bot-Namen kann der resultierende JID die XMPP-Längenbegrenzung (1023 Bytes für localpart) überschreiten.

**Auswirkung:** ejabberd-Registrierung kann bei langen Bot-Namen fehlschlagen.

**Fix:** Länge auf max. 64 Zeichen begrenzen:
```vala
string sanitized = name.down().replace(...);
if (sanitized.length > 50) sanitized = sanitized.substring(0, 50);
```

---

### BUG-13: Konversation-Historien unbegrenzt im Speicher (AI)
**Datei:** `ai_integration.vala`, Zeile 36  
**Beschreibung:** Die `histories` HashMap speichert maximal `MAX_HISTORY` (20) Nachrichten pro Bot+JID-Kombination, aber es gibt **kein Limit** für die Anzahl verschiedener Kombinationen. Wenn viele unterschiedliche JIDs an einen Bot schreiben, wächst die HashMap unbegrenzt.

**Auswirkung:** Speicherleck bei Bots mit vielen verschiedenen Kontakten.

**Fix:** LRU-Cache mit maximal N Einträgen implementieren, oder periodisch alte Einträge aufräumen.

---

### BUG-14: Gemini API-Key erscheint in der URL (Query-Parameter)
**Datei:** `ai_integration.vala`, Zeile 323  
**Beschreibung:** Die Gemini-API wird mit dem Key als URL-Query-Parameter aufgerufen:
```vala
string url = "%s/models/%s:generateContent?key=%s".printf(base_url, model, api_key);
```
URL-Parameter können in Logs, Proxys und Browser-History gespeichert werden. Alle anderen Provider verwenden Header-basierte Auth.

**Auswirkung:** Der API-Key kann in HTTP-Logs oder Proxy-Logs erscheinen.

**Fix:** Dies ist leider das Standard-Verfahren der Google Gemini API. Als Mitigation: in der Dokumentation darauf hinweisen und ggf. den URL-Log-Level reduzieren.

---

### BUG-15: `send_telegram_message` sendet HTML ohne Escaping
**Datei:** `telegram_bridge.vala`, Zeile 575  
**Beschreibung:** Die Methode setzt `parse_mode: "HTML"` im Telegram-API-Aufruf, aber der Nachrichtentext wird **nicht** HTML-escapt. XMPP-Nachrichten mit `<`, `>`, `&` können das Telegram-Rendering stören oder die Nachricht abschneiden.

**Auswirkung:** Nachrichten mit HTML-Zeichen werden verstümmelt oder von Telegram abgelehnt (400 Bad Request).

**Fix:** Entweder `parse_mode` entfernen (Telegram escaped dann automatisch) oder den Text vor dem Senden HTML-escapen.

---

### BUG-16: `addr.device_id = 0` zur Verhinderung von Speicherfreigabe
**Datei:** `bot_omemo.vala`, Zeilen 358, 583  
**Beschreibung:** Der Code setzt `addr.device_id = 0;` mit dem Kommentar "prevent premature free". Dies deutet auf einen Ownership-Bug in den C-Bindings hin, wo `Omemo.Address.device_id` das `Address`-Objekt beeinflusst. Ein Workaround, der auf undokumentiertem Verhalten basiert und bei Updates der Bibliothek brechen kann.

**Auswirkung:** Potenzielle Use-after-free wenn die Bibliothek aktualisiert wird.

**Fix:** Den Lifecycle des `Address`-Objekts korrekt verwalten (z.B. Referenz halten bis der Cipher fertig ist).

---

### BUG-17: Keine Zeitzone-Prüfung bei Session-Persistenz
**Datei:** `bot_omemo.vala`, `persist_session()` Methode  
**Beschreibung:** Jede Ratchet-State-Änderung löst ein vollständiges Lesen + Parsen + Neuschreiben der gesamten Sessions-JSON aus der Datenbank aus. Bei vielen Sessions (z.B. 50+ Kontakte) kann dies bei jeder eingehenden Nachricht zu erheblicher I/O führen.

**Auswirkung:** Performance-Degradierung bei vielen OMEMO-Sessions.

**Fix:** Sessions einzeln speichern (z.B. `omemo_session:<bot_id>:<jid>:<device_id>`) statt alle in einem JSON-Blob.

---

## NIEDRIG

### BUG-18: `gnutls_global_init()` bei jedem Zertifikat-Aufruf
**Datei:** `cert_gen.c`, Zeile 77  
**Beschreibung:** `gnutls_global_init()` wird bei jedem Aufruf von `dinox_generate_self_signed_cert()` aufgerufen, ohne korrespondierendes `gnutls_global_deinit()`. Laut GnuTLS-Dokumentation ist Mehrfach-Init sicher (Reference-Counting), aber es ist unsauber.

**Auswirkung:** Minimal — GnuTLS handhabt dies intern korrekt.

**Fix:** Einmalig beim Plugin-Start initialisieren und beim Shutdown deinitialisieren.

---

### BUG-19: Fehlende `\t`-Escape in `escape_json()` aller Dateien
**Datei:** `ai_integration.vala` Z.555, `telegram_bridge.vala` Z.635, `message_router.vala` Z.1759  
**Beschreibung:** Alle drei separaten `escape_json()`-Implementierungen (Code-Duplikat!) escapen identisch nur `\`, `"`, `\n`, `\r`. Tab-Zeichen, Backspace, Form-Feed und NULL werden nicht escaped. Siehe auch BUG-05.

**Auswirkung:** Ungültiges JSON bei Kontrollzeichen.

**Fix:** Zentrale `escape_json()`-Funktion in einer Utility-Klasse, mit vollständigem RFC-8259-Escaping.

---

### BUG-20: Rate-Limiter `cleanup()` wird nie automatisch aufgerufen
**Datei:** `rate_limiter.vala`  
**Beschreibung:** Die `cleanup()`-Methode zum Entfernen abgelaufener Rate-Windows existiert, wird aber nirgends periodisch aufgerufen.

**Auswirkung:** Langsamer Speicherzuwachs der `windows`-HashMap über die Laufzeit.

**Fix:** Periodischen Cleanup-Timer hinzufügen (z.B. alle 300 Sekunden).

---

### BUG-21: Webhook-Retry bei nicht-transienten Fehlern
**Datei:** `webhook_dispatcher.vala`  
**Beschreibung:** Der Dispatcher macht 3 Retries mit Exponential-Backoff bei **jedem** Fehler, einschließlich 4xx-Client-Fehlern (400, 401, 403, 404). Nur Server-Fehler (5xx) und Netzwerk-Fehler sollten wiederholt werden.

**Auswirkung:** Unnötige Wiederholungen bei permanenten Fehlern, die nie erfolgreich sein werden.

**Fix:** Bei HTTP 4xx sofort abbrechen:
```vala
if (status >= 400 && status < 500) break; // Don't retry client errors
```

---

### BUG-22: `delete_dedicated_bot()` Fire-and-Forget ohne Fehlerbehandlung
**Datei:** `botfather_handler.vala`, Zeile ~320  
**Beschreibung:** Die Löschung dedizierter Bots via ejabberd-API wird als Fire-and-Forget behandelt (`unregister.begin()` ohne Await). Wenn die ejabberd-Deregistrierung fehlschlägt, bleibt das XMPP-Konto als Zombie auf dem Server bestehen.

**Auswirkung:** Verwaiste ejabberd-Konten bei Fehlern.

**Fix:** Auf das Ergebnis warten und bei Fehler loggen/warnen. Ggf. Liste "pending deletes" für Retry.

---

## Hinweise (kein Fix erforderlich)

1. **API-Key-Speicherung im Klartext:** AI- und Telegram-Keys werden als Klartext in der SQLite-Settings-Tabelle gespeichert. Bei Produktivbetrieb wäre Verschlüsselung empfehlenswert.

2. **Self-signed Cert akzeptiert überall:** `session_pool.vala` akzeptiert blindlings alle Zertifikate (`return true`). Dies ist für den Entwicklungsbetrieb akzeptabel, sollte in Produktivumgebungen konfigurierbar sein.

3. **Dreifache Code-Duplikation von `escape_json()`:** Existiert identisch in `ai_integration.vala`, `telegram_bridge.vala` und `message_router.vala`. Sollte in eine gemeinsame Utility-Klasse extrahiert werden.

4. **10-Jahres-Zertifikat:** `cert_gen.c` generiert Zertifikate mit 10 Jahren Gültigkeit. Für Self-signed akzeptabel, aber lang.
