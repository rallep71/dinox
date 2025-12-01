# Disappearing Messages (Selbst-löschende Nachrichten)

## 📋 Feature-Übersicht

Automatisches Löschen von Nachrichten nach einer vom Benutzer gewählten Zeitspanne - ähnlich wie bei WhatsApp.

**Server-Löschung:** ✅ DinoX nutzt **XEP-0424 Message Retraction** - eigene Nachrichten werden auch auf dem Server gelöscht (wenn unterstützt)!

---

## 🔍 Tiefgründige Code-Analyse

### Existierende Lösch-Infrastruktur

#### 1. MessageDeletion Service (`libdino/src/service/message_deletion.vala`)

```
delete_globally(conversation, content_item)
├── Für 1:1 Chat: XEP-0424 Message Retraction
│   └── MessageRetraction.set_retract_id(stanza, message_id)
├── Für MUC (eigene): XEP-0424 Message Retraction
│   └── stanza.type_ = MessageStanza.TYPE_GROUPCHAT
└── Für MUC (fremde): XEP-0425 Message Moderation
    └── MessageModeration.moderate(stream, muc_jid, message_id)
```

**Wichtige Erkenntnis:** `delete_globally()` funktioniert nur für:
- ✅ Eigene Nachrichten → XEP-0424 Retraction
- ✅ Fremde Nachrichten in MUC (als Moderator) → XEP-0425 Moderation
- ❌ Fremde Nachrichten in 1:1 Chat → NUR lokal möglich!

#### 2. ContentItemStore (`libdino/src/service/content_item_store.vala`)

Verfügbare Abfrage-Methoden:
```vala
get_n_latest(conversation, count)     // Holt die neuesten N Items
get_before(conversation, item, count) // Holt Items VOR einem bestimmten Item
get_after(conversation, item, count)  // Holt Items NACH einem bestimmten Item
get_latest(conversation)              // Holt das neueste Item
```

**FEHLT:** `get_items_before_time(conversation, DateTime cutoff)` → Muss implementiert werden!

#### 3. ContentItem Klassen (`content_item_store.vala` Zeile 345-450)

```
ContentItem (abstract)
├── id: int
├── type_: string  
├── jid: Jid
├── time: DateTime     ← WICHTIG für Zeit-basierte Löschung
├── encryption: Encryption
└── mark: Message.Marked

MessageItem extends ContentItem
├── message: Message
└── conversation: Conversation

FileItem extends ContentItem
├── file_transfer: FileTransfer
└── conversation: Conversation

CallItem extends ContentItem
└── call: Call
```

#### 4. Conversation Entity (`libdino/src/entity/conversation.vala`)

Existierende Properties:
```vala
public int id { get; set; }
public DateTime? history_cleared_at { get; set; }  // Bereits vorhanden!
public NotifySetting notify_setting { get; set; }
public Setting send_typing { get; set; }
public Setting send_marker { get; set; }
public int pinned { get; set; }
```

**Pattern für neues Property:**
1. Property in Entity-Klasse
2. Laden in `from_row()` Konstruktor
3. Speichern in `persist()`
4. Update in `on_update()` Handler

#### 5. Database Schema (`libdino/src/service/database.vala`)

ConversationTable (Zeile 306-327):
```vala
public Column<long> history_cleared_at = new Column.Long("history_cleared_at") { default="0", min_version=32 };
// → message_expiry_seconds muss als min_version=34 hinzugefügt werden
```

**Aktuelle DB-Version:** 33 (Zeile 19)

#### 6. UI: Conversation Details (`main/src/ui/conversation_details.vala`)

Einstellungen werden in `set_about_rows()` hinzugefügt:
```vala
// Zeile ~233 - Nach den anderen Settings:
view_model.settings_rows.append(preferences_row);
```

Verwendbare UI-Komponenten:
- `PreferencesRow.ComboBox` → Dropdown mit Optionen
- `PreferencesRow.Toggle` → An/Aus Schalter
- `PreferencesRow.Button` → Aktion auslösen

#### 7. Chat-Banner System (`main/src/ui/conversation_content_view/`)

**Architektur:**
```
ConversationView
├── notification_revealer (GtkRevealer)
│   └── notifications (GtkBox)
│       ├── SubscriptionNotification
│       └── [NEU] ExpiryNotification
└── subscription_notification.init(conversation, this)
```

**API:**
```vala
conversation_view.add_notification(widget);     // Zeigt Banner
conversation_view.remove_notification(widget);  // Entfernt Banner
```

Banner werden automatisch mit Animation eingeblendet (Zeile 509-515).

---

## ✅ Server-Löschung wird unterstützt!

DinoX nutzt bereits **XEP-0424 (Message Retraction)** und **XEP-0425 (Message Moderation)**:

```vala
// In delete_globally():
Xmpp.Xep.MessageRetraction.set_retract_id(stanza, message_id_to_delete);
stream.get_module(MessageModule.IDENTITY).send_message.begin(stream, stanza);
```

### Was passiert bei automatischer Löschung:

| Nachrichten-Typ | Lösch-Methode | Server-Löschung |
|-----------------|---------------|-----------------|
| Eigene (1:1 Chat) | `delete_globally()` → XEP-0424 | ✅ Ja |
| Eigene (MUC) | `delete_globally()` → XEP-0424 | ✅ Ja |
| Empfangene (1:1 Chat) | `delete_locally()` | ❌ Nur lokal |
| Empfangene (MUC als Mod) | `delete_globally()` → XEP-0425 | ✅ Ja |

### Voraussetzung:
- Server muss XEP-0424/0425 unterstützen
- ejabberd: `mod_message_retract` aktiviert
- Prosody: `mod_message_retract` Plugin

---

## 🎯 Geplante Funktionen

1. **Pro-Conversation Einstellung** - Jeder Chat kann unterschiedliche Ablaufzeiten haben
2. **Flexible Timer-Optionen** - 1h, 24h, 7 Tage, 30 Tage, Nie
3. **Chat-Hinweis/Banner** - Sichtbare Info wenn Nachrichten automatisch gelöscht werden
4. **Hintergrund-Job** - Regelmäßige Prüfung und Löschung alter Nachrichten
5. **Dateien werden mitgelöscht** - Auch Bilder/Anhänge werden entfernt (bei lokaler Löschung)
6. **Intelligente Löschung** - Eigene Nachrichten global, empfangene lokal

---

## 📁 Detaillierter Implementierungsplan

### Schritt 1: Datenbank-Schema (`database.vala`)

**Datei:** `libdino/src/service/database.vala`

```vala
// Zeile 19: VERSION erhöhen
private const int VERSION = 34;

// Zeile ~322 in ConversationTable nach history_cleared_at:
public Column<int> message_expiry_seconds = new Column.Integer("message_expiry_seconds") { default="0", min_version=34 };

// Zeile ~325 in init():
init({id, account_id, jid_id, resource, active, active_last_changed, last_active, type_, encryption, 
      read_up_to, read_up_to_item, notification, send_typing, send_marker, pinned, history_cleared_at,
      message_expiry_seconds});  // ← Hinzufügen
```

---

### Schritt 2: Conversation Entity (`conversation.vala`)

**Datei:** `libdino/src/entity/conversation.vala`

```vala
// Nach Zeile 55 (history_cleared_at):
public int message_expiry_seconds { get; set; default = 0; }

// In from_row() nach history_cleared_at (Zeile ~90):
message_expiry_seconds = row[db.conversation.message_expiry_seconds];

// In persist() nach history_cleared_at (Zeile ~132):
insert.value(db.conversation.message_expiry_seconds, message_expiry_seconds);

// In on_update() switch statement (nach "history-cleared-at" case):
case "message-expiry-seconds":
    update.set(db.conversation.message_expiry_seconds, message_expiry_seconds); break;
```

---

### Schritt 3: ContentItemStore - Neue Methode (`content_item_store.vala`)

**Datei:** `libdino/src/service/content_item_store.vala`

Nach `get_after()` (Zeile ~288) hinzufügen:

```vala
public Gee.List<ContentItem> get_items_older_than(Conversation conversation, DateTime cutoff_time) {
    long cutoff_unix = (long) cutoff_time.to_unix();
    QueryBuilder select = db.content_item.select()
        .where("time < ?", { cutoff_unix.to_string() })
        .with(db.content_item.conversation_id, "=", conversation.id)
        .with(db.content_item.hide, "=", false)
        .order_by(db.content_item.time, "ASC");

    return get_items_from_query(select, conversation);
}
```

---

### Schritt 4: MessageDeletion - Timer-basierte Löschung (`message_deletion.vala`)

**Datei:** `libdino/src/service/message_deletion.vala`

```vala
// Im Konstruktor nach stream_interactor.get_module(MessageProcessor.IDENTITY)...:
// Starte Timer für automatische Löschung (alle 5 Minuten)
Timeout.add_seconds(60 * 5, check_expired_messages);

// Neue Methoden am Ende der Klasse:
private bool check_expired_messages() {
    var now = new DateTime.now_utc();
    var content_item_store = stream_interactor.get_module(ContentItemStore.IDENTITY);
    
    foreach (Account account in stream_interactor.get_accounts()) {
        foreach (Conversation conversation in db.get_conversations(account)) {
            if (conversation.message_expiry_seconds > 0) {
                delete_expired_messages(conversation, now, content_item_store);
            }
        }
    }
    return true;  // Timer weiterlaufen lassen
}

private void delete_expired_messages(Conversation conversation, DateTime now, ContentItemStore content_item_store) {
    var cutoff_time = now.add_seconds(-conversation.message_expiry_seconds);
    var items = content_item_store.get_items_older_than(conversation, cutoff_time);
    
    debug("Checking expired messages for %s: %d items before %s", 
          conversation.counterpart.to_string(), items.size, cutoff_time.to_string());
    
    foreach (ContentItem item in items) {
        // Prüfen ob es unsere eigene Nachricht ist
        bool is_own = false;
        if (item is MessageItem) {
            is_own = ((MessageItem) item).message.direction == Message.DIRECTION_SENT;
        } else if (item is FileItem) {
            is_own = ((FileItem) item).file_transfer.direction == FileTransfer.DIRECTION_SENT;
        }
        
        if (is_own && can_delete_for_everyone(conversation, item)) {
            // Eigene Nachricht: Global löschen (Server + lokal)
            delete_globally(conversation, item);
        } else {
            // Empfangene Nachricht: Nur lokal löschen
            delete_locally(conversation, item, conversation.account.bare_jid);
        }
    }
}
```

---

### Schritt 5: UI Dropdown (`conversation_details.vala`)

**Datei:** `main/src/ui/conversation_details.vala`

In `set_about_rows()` nach den MUC-Settings (vor der schließenden Klammer):

```vala
// Disappearing Messages - für alle Konversationstypen
var expiry_row = new ViewModel.PreferencesRow.ComboBox();
expiry_row.title = _("Auto-delete messages");
expiry_row.items.add(_("Never"));
expiry_row.items.add(_("After 1 hour"));
expiry_row.items.add(_("After 24 hours"));
expiry_row.items.add(_("After 7 days"));
expiry_row.items.add(_("After 30 days"));

// Aktuellen Wert setzen
switch (model.conversation.message_expiry_seconds) {
    case 3600: expiry_row.active_item = 1; break;
    case 86400: expiry_row.active_item = 2; break;
    case 604800: expiry_row.active_item = 3; break;
    case 2592000: expiry_row.active_item = 4; break;
    default: expiry_row.active_item = 0; break;
}

// Bei Änderung speichern
expiry_row.notify["active-item"].connect(() => {
    switch (expiry_row.active_item) {
        case 1: model.conversation.message_expiry_seconds = 3600; break;
        case 2: model.conversation.message_expiry_seconds = 86400; break;
        case 3: model.conversation.message_expiry_seconds = 604800; break;
        case 4: model.conversation.message_expiry_seconds = 2592000; break;
        default: model.conversation.message_expiry_seconds = 0; break;
    }
});

view_model.settings_rows.append(expiry_row);
```

---

### Schritt 6: Banner-Notification (`expiry_notification.vala`)

**Neue Datei:** `main/src/ui/conversation_content_view/expiry_notification.vala`

```vala
using Gtk;
using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class ExpiryNotification : Object {
    private StreamInteractor stream_interactor;
    private Conversation? conversation;
    private ConversationView? conversation_view;
    private Box? current_notification;
    private ulong notify_handler_id = 0;

    public ExpiryNotification(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void init(Conversation conversation, ConversationView conversation_view) {
        // Cleanup vorherige Verbindung
        if (this.conversation != null && notify_handler_id != 0) {
            this.conversation.disconnect(notify_handler_id);
            notify_handler_id = 0;
        }
        
        this.conversation = conversation;
        this.conversation_view = conversation_view;
        
        update_notification();
        
        // Bei Änderung der Einstellung aktualisieren
        notify_handler_id = conversation.notify["message-expiry-seconds"].connect(update_notification);
    }

    public void close() {
        if (current_notification != null && conversation_view != null) {
            conversation_view.remove_notification(current_notification);
            current_notification = null;
        }
        if (conversation != null && notify_handler_id != 0) {
            conversation.disconnect(notify_handler_id);
            notify_handler_id = 0;
        }
    }

    private void update_notification() {
        // Alte Notification entfernen
        if (current_notification != null) {
            conversation_view.remove_notification(current_notification);
            current_notification = null;
        }
        
        if (conversation.message_expiry_seconds == 0) return;
        
        // Neue Notification erstellen
        current_notification = new Box(Orientation.HORIZONTAL, 8) { margin_start = 8, margin_end = 8 };
        
        var icon = new Image.from_icon_name("alarm-symbolic");
        icon.add_css_class("warning");
        
        string time_text = get_time_text(conversation.message_expiry_seconds);
        var label = new Label(_("Messages in this chat will be deleted %s").printf(time_text));
        
        current_notification.append(icon);
        current_notification.append(label);
        
        conversation_view.add_notification(current_notification);
    }
    
    private string get_time_text(int seconds) {
        switch (seconds) {
            case 3600: return _("after 1 hour");
            case 86400: return _("after 24 hours");
            case 604800: return _("after 7 days");
            case 2592000: return _("after 30 days");
            default: return "";
        }
    }
}

}
```

---

### Schritt 7: Integration in ConversationView (`conversation_view.vala`)

**Datei:** `main/src/ui/conversation_content_view/conversation_view.vala`

```vala
// Zeile ~43 nach subscription_notification:
private ExpiryNotification expiry_notification;

// In init() Zeile ~127 nach subscription_notification = new...:
expiry_notification = new ExpiryNotification(stream_interactor);

// In display_conversation() Zeile ~437 nach subscription_notification.init():
expiry_notification.init(conversation, this);

// Im close-Teil (wenn vorhanden) oder bei Conversation-Wechsel:
// expiry_notification.close();
```

---

### Schritt 8: Meson Build (`main/meson.build`)

**Datei:** `main/meson.build`

In der `sources` Liste nach `subscription_notification.vala`:
```meson
'src/ui/conversation_content_view/expiry_notification.vala',
```

---

## 📋 Implementierungs-Checkliste

| # | Schritt | Datei | Zeilen | Status |
|---|---------|-------|--------|--------|
| 1 | DB VERSION = 34 | database.vala | 19 | ⬜ |
| 2 | Neue DB-Spalte | database.vala | ~322 | ⬜ |
| 3 | DB init() update | database.vala | ~325 | ⬜ |
| 4 | Entity Property | conversation.vala | ~55 | ⬜ |
| 5 | Entity from_row() | conversation.vala | ~90 | ⬜ |
| 6 | Entity persist() | conversation.vala | ~132 | ⬜ |
| 7 | Entity on_update() | conversation.vala | ~220 | ⬜ |
| 8 | get_items_older_than() | content_item_store.vala | ~288 | ⬜ |
| 9 | Timer im Konstruktor | message_deletion.vala | ~37 | ⬜ |
| 10 | check_expired_messages() | message_deletion.vala | Ende | ⬜ |
| 11 | delete_expired_messages() | message_deletion.vala | Ende | ⬜ |
| 12 | UI Dropdown | conversation_details.vala | ~285 | ⬜ |
| 13 | ExpiryNotification Klasse | expiry_notification.vala | NEU | ⬜ |
| 14 | ConversationView Integration | conversation_view.vala | ~43,127,437 | ⬜ |
| 15 | Meson sources | meson.build | sources | ⬜ |
| 16 | Build & Test | - | - | ⬜ |
| 17 | CHANGELOG & Version | - | - | ⬜ |

---

## ⚠️ Bekannte Einschränkungen

1. **Server-Abhängig** - Globale Löschung nur wenn Server XEP-0424/0425 unterstützt
2. **Empfangene Nachrichten** - Werden NUR lokal gelöscht (XEP-0424 nur für eigene Nachrichten)
3. **Timer-Intervall** - Nachrichten werden alle 5 Minuten geprüft, nicht sekundengenau
4. **Offline-Nachrichten** - Werden erst bei nächstem App-Start geprüft

---

## 🚀 Bereit zur Implementierung?

Der Plan ist vollständig analysiert und dokumentiert. 
Geschätzte Implementierungszeit: ~1-2 Stunden

**Sag mir Bescheid wenn ich beginnen soll!**

