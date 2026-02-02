# OpenPGP Porting Guide: xmppwin → Dino Linux

## Übersicht

Dieses Dokument beschreibt alle Änderungen, die im Windows-Port (xmppwin) für die vollständige OpenPGP-Unterstützung (XEP-0027, XEP-0373, XEP-0374) gemacht wurden.

**Datum:** Februar 2026  
**Getestet mit:** DinoX Windows ↔ Monocles Android

---

## 1. Neue Dateien (müssen nach Linux kopiert werden)

### xmpp-vala/src/module/xep/

| Datei | Beschreibung |
|-------|--------------|
| `0373_openpgp.vala` | XEP-0373 PubSub Key Publishing Module |
| `0374_openpgp_content.vala` | XEP-0374 Signcrypt Content Elements |

### plugins/openpgp/src/

| Datei | Beschreibung |
|-------|--------------|
| `gpg_cli_helper.vala` | **NUR WINDOWS** - GPG CLI Backend (ersetzt GPGME) |
| `xep0373_key_manager.vala` | XEP-0373 Key Manager (plattformunabhängig) |
| `key_management_dialog.vala` | Neuer Key Management Dialog |

---

## 2. Geänderte Dateien

### 2.1 plugins/openpgp/src/plugin.vala

**Änderungen:**
- XEP-0373 Manager initialisieren
- XEP-0373/0374 Module zu Account-Modulen hinzufügen
- Windows-spezifische GNUPGHOME-Pfadkonvertierung
- gpg-agent.conf mit Pinentry konfigurieren

**Wichtige Code-Abschnitte:**

```vala
// In registered():
// Initialize XEP-0373 key manager
this.xep0373_manager = new Xep0373KeyManager(app.stream_interactor, db);

// Connect to conversation activation for proactive key fetching
app.stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY)
    .conversation_activated.connect((conversation) => {
        if (conversation.type_ == Conversation.Type.CHAT && this.xep0373_manager != null) {
            this.xep0373_manager.request_keys.begin(conversation.account, conversation.counterpart.bare_jid);
        }
    });

// In on_initialize_account_modules():
// Add XEP-0373 module (PubSub key distribution)
modules.add(new Xmpp.Xep.OpenPgp.Module());

// Add XEP-0374 module (signcrypt encryption)
modules.add(new Xmpp.Xep.OpenPgpContent.Module());
```

### 2.2 plugins/openpgp/src/stream_module.vala

**Änderungen:**
- `encrypt_0374()` Methode für XEP-0374 Signcrypt
- `gpg_sign()` verwendet jetzt `--detach-sign` (NICHT `--clearsign`)
- Signature-Extraktion für detached signatures
- `extract_pgp_data()` Helper für Base64-Extraktion

**Wichtiger Fix (XEP-0027 Kompatibilität):**
```vala
// VORHER (falsch):
signed = GPGHelper.sign(str, GPGHelper.SIG_MODE_CLEAR, key);

// NACHHER (korrekt):
signed = GPGHelper.sign(str, 1, key);  // 1 = DETACH mode

// Signature-Extraktion für detached format:
int begin_marker = signed.index_of("-----BEGIN PGP SIGNATURE-----");
int content_start = signed.index_of("\n\n", begin_marker) + 2;
int end_marker = signed.index_of("-----END PGP SIGNATURE-----");
string base64_content = signed.substring(content_start, end_marker - content_start);
```

### 2.3 plugins/openpgp/src/manager.vala

**Änderungen:**
- `check_xep0374_support()` via EntityInfo Cache (Service Discovery)
- Automatischer Fallback XEP-0374 → XEP-0027
- XEP-0373 Manager Integration

```vala
// Service Discovery für XEP-0374:
private bool check_xep0374_support(Account account, Jid jid) {
    var entity_info = stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY);
    if (entity_info == null) return false;
    
    // Cached lookup (synchronous, crash-safe)
    bool has_feature = entity_info.has_feature_cached(account, jid.bare_jid, NS_OPENPGP_IM);
    if (has_feature) return true;
    
    // Offline DB cache
    has_feature = entity_info.has_feature_offline(account, jid.bare_jid, NS_OPENPGP_IM);
    return has_feature;
}

// In check_encrypt():
if (check_xep0374_support(conversation.account, conversation.counterpart)) {
    encrypted = stream.get_module<Module>(Module.IDENTITY).encrypt_0374(message_stanza, keys);
}
if (!encrypted) {
    // Fallback to XEP-0027
    encrypted = stream.get_module<Module>(Module.IDENTITY).encrypt(message_stanza, keys);
}
```

### 2.4 plugins/openpgp/src/encryption_preferences_entry.vala

**Änderungen:**
- Passphrase-Prüfung vor Key-Auswahl
- `resend_presence()` nach Key-Auswahl (wichtig für XEP-0027!)

```vala
// Nach Key-Auswahl Presence neu senden:
private void save_key_selection(string key_fpr) {
    // ... key speichern ...
    
    // XEP-0373 republish
    if (plugin.xep0373_manager != null) {
        plugin.xep0373_manager.republish_key(current_account);
    }
    
    // WICHTIG: Presence neu senden für XEP-0027
    var presence_manager = plugin.app.stream_interactor.get_module<Dino.PresenceManager>(Dino.PresenceManager.IDENTITY);
    if (presence_manager != null) {
        presence_manager.resend_presence(current_account);
    }
}
```

### 2.5 libdino/src/service/presence_manager.vala

**Neue Methode hinzugefügt:**

```vala
public void resend_presence(Account account) {
    XmppStream? stream = stream_interactor.get_stream(account);
    if (stream == null) return;
    
    Presence.Stanza presence = new Presence.Stanza();
    presence.type_ = Presence.Stanza.TYPE_AVAILABLE;
    
    string? status = account.status;
    if (status != null && status.length > 0) {
        presence.status = status;
    }
    
    stream.get_module<Presence.Module>(Presence.Module.IDENTITY).send_presence(stream, presence);
}
```

---

## 3. Windows-spezifische Änderungen (NICHT nach Linux portieren)

### 3.1 gpg_cli_helper.vala

Diese Datei ist **nur für Windows** und ersetzt GPGME. Für Linux weiterhin GPGME verwenden.

**Wichtige Konzepte die auch für GPGME gelten:**
- Mutex für serialisierte GPG-Aufrufe
- Temp-Dateien für interaktive Operationen (Pinentry)
- Status-File für Signature-Verification

### 3.2 Plugin GNUPGHOME-Handling

```vala
#if WINDOWS
    // Convert Unix paths to Windows paths
    if (openpgp_gnupg_home.has_prefix("/")) {
        // /c/Users... → C:\Users...
    }
    // Configure pinentry-w32
#endif
```

---

## 4. meson.build Änderungen

### xmpp-vala/meson.build

```meson
# Neue Dateien hinzufügen:
'src/module/xep/0373_openpgp.vala',
'src/module/xep/0374_openpgp_content.vala',
```

### plugins/openpgp/meson.build

```meson
# Neue Dateien:
'src/xep0373_key_manager.vala',
'src/key_management_dialog.vala',

# Windows-only:
if host_machine.system() == 'windows'
    sources += 'src/gpg_cli_helper.vala'
endif
```

---

## 5. Wichtige Fixes (plattformunabhängig)

### 5.1 Detached Signature Format (XEP-0027)

Das originale Dino verwendet möglicherweise `--clearsign`, aber XEP-0027 erwartet detached signatures:

```
# FALSCH (clearsign):
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

[message]
-----BEGIN PGP SIGNATURE-----
[signature]
-----END PGP SIGNATURE-----

# KORREKT (detach-sign):
-----BEGIN PGP SIGNATURE-----

[base64 signature only]
-----END PGP SIGNATURE-----
```

### 5.2 Keyserver Integration

```vala
// Download key from keyserver when missing
if (verify_result.key_missing) {
    bool imported = GPGHelper.download_key_from_keyserver(verify_result.key_id);
    if (imported) {
        verify_result = verify_signature(sig, signed_data);  // Re-verify
    }
}
```

### 5.3 XEP-0373 Self-Test

Nach dem Publizieren eigenen Key abrufen um zu verifizieren:

```vala
// Self-test after publishing
var self_keys = yield fetch_public_keys_list(stream, own_jid.bare_jid);
if (self_keys != null && self_keys.size > 0) {
    debug("XEP-0373: Self-test SUCCESS");
}
```

---

## 6. Namespaces

```vala
// XEP-0027 (Legacy)
public const string NS_URI = "jabber:x:encrypted";
public const string NS_URI_SIGNED = "jabber:x:signed";
public const string NS_URI_ENCRYPTED = "jabber:x:encrypted";

// XEP-0373 (PubSub Keys)
public const string NS_URI = "urn:xmpp:openpgp:0";
public const string NS_URI_PUBKEYS = "urn:xmpp:openpgp:0:public-keys";

// XEP-0374 (Signcrypt)
public const string NS_OPENPGP_IM = "urn:xmpp:openpgp:0:im";
```

---

## 7. Portierungsreihenfolge

1. **xmpp-vala Module kopieren:**
   - `0373_openpgp.vala`
   - `0374_openpgp_content.vala`

2. **Plugin-Dateien kopieren:**
   - `xep0373_key_manager.vala`
   - `key_management_dialog.vala` (optional, UI)

3. **Bestehende Dateien patchen:**
   - `stream_module.vala` (encrypt_0374, gpg_sign fix)
   - `manager.vala` (XEP-0374 support check)
   - `plugin.vala` (XEP-0373 init)
   - `presence_manager.vala` (resend_presence)

4. **meson.build aktualisieren**

5. **Testen mit Monocles/Conversations**

---

## 8. GPG Backend Abstraktion (Empfohlen für saubere Lösung)

Für eine saubere plattformübergreifende Lösung:

```vala
// gpg_backend.vala - Interface
public interface GPGBackend : Object {
    public abstract string sign(string text, int mode, Key key) throws Error;
    public abstract string encrypt(string text, Key[] keys) throws Error;
    public abstract string decrypt(string armored) throws Error;
    public abstract SignatureVerifyResult verify_signature(string sig, string? text) throws Error;
    public abstract Gee.List<Key> get_keylist(string? pattern = null, bool secret_only = false) throws Error;
}

// gpg_gpgme_backend.vala - Linux
public class GPGMEBackend : Object, GPGBackend {
    // Bestehende GPGME-Implementierung
}

// gpg_cli_backend.vala - Windows
public class GPGCLIBackend : Object, GPGBackend {
    // CLI-basierte Implementierung
}

// gpg_helper.vala - Factory
public class GPGHelper {
    private static GPGBackend? backend = null;
    
    public static GPGBackend get_backend() {
        if (backend == null) {
#if WINDOWS
            backend = new GPGCLIBackend();
#else
            backend = new GPGMEBackend();
#endif
        }
        return backend;
    }
}
```

---

## 9. Bekannte Probleme und Lösungen

| Problem | Lösung |
|---------|--------|
| GLib crash `g_win32_pop_invalid_parameter_handler` | Subprocess statt Process.spawn_sync, Temp-Files statt Pipes |
| Radix64 errors bei parallelen GPG-Aufrufen | Mutex (`GLib.Mutex gpg_mutex`) |
| Signature-Format inkompatibel | `--detach-sign` statt `--clearsign` |
| Key nicht erkannt nach Auswahl | `resend_presence()` aufrufen |
| Keys.openpgp.org ohne UID | API-Fallback `/vks/v1/by-keyid/` |

---

## 10. Dateien zum Vergleichen

```bash
# Im xmppwin Ordner:
diff -u ../dino/plugins/openpgp/src/stream_module.vala plugins/openpgp/src/stream_module.vala
diff -u ../dino/plugins/openpgp/src/manager.vala plugins/openpgp/src/manager.vala
diff -u ../dino/plugins/openpgp/src/plugin.vala plugins/openpgp/src/plugin.vala
diff -u ../dino/libdino/src/service/presence_manager.vala libdino/src/service/presence_manager.vala

# Neue Dateien (existieren nicht in dino):
ls -la xmpp-vala/src/module/xep/0373_openpgp.vala
ls -la xmpp-vala/src/module/xep/0374_openpgp_content.vala
ls -la plugins/openpgp/src/xep0373_key_manager.vala
ls -la plugins/openpgp/src/gpg_cli_helper.vala
```

---

**Autor:** GitHub Copilot  
**Basierend auf:** xmppwin OpenPGP Implementation Session, Februar 2026
