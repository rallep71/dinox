#!/usr/bin/env python3
"""
Translate untranslated DinoX plugin strings into DE, FR, ES.

Safety features:
1. Validates format specifiers (%s, %d, %lld, etc.) match between source/target
2. Validates escape sequences (\n, \t) are preserved
3. Validates XML entities (&amp; etc.) are preserved
4. Checks bracket/parenthesis balance
5. Runs msgfmt --check after writing
6. Runs pofilter for comprehensive QA
7. Creates backup before any changes

Usage:
    python3 scripts/translate_plugins.py          # dry-run (default)
    python3 scripts/translate_plugins.py --apply  # apply changes
    python3 scripts/translate_plugins.py --check  # validate only
"""

import polib
import re
import subprocess
import shutil
import sys
import os
from pathlib import Path

# Import FR and ES dictionaries from sibling modules
sys.path.insert(0, str(Path(__file__).resolve().parent))
from translations_fr import FR
from translations_es import ES

BASE = Path(__file__).resolve().parent.parent
PO_DIR = BASE / "main" / "po"

# ─── Format specifier regex ─────────────────────────────────────────
FMT_RE = re.compile(r'%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh?|ll?|[Lzjt])?[diouxXeEfFgGaAcspn%]')
# Matches: %s, %d, %1$s, %02d, %lld, %%

def extract_format_specs(s):
    """Return sorted list of format specifiers in a string."""
    return sorted(FMT_RE.findall(s))

def validate_translation(msgid, msgstr):
    """Validate a translation. Returns (ok, errors)."""
    errors = []
    if not msgstr:
        return True, []  # Empty is fine (untranslated)

    # 1. Format specifiers must match exactly
    src_fmts = extract_format_specs(msgid)
    dst_fmts = extract_format_specs(msgstr)
    if src_fmts != dst_fmts:
        errors.append(f"Format mismatch: src={src_fmts} dst={dst_fmts}")

    # 2. Newlines: count must match (important for UI layout)
    src_nl = msgid.count('\n')
    dst_nl = msgstr.count('\n')
    if src_nl != dst_nl:
        errors.append(f"Newline count: src={src_nl} dst={dst_nl}")

    # 3. XML entities must be preserved
    for entity in ['&amp;', '&lt;', '&gt;']:
        if entity in msgid and entity not in msgstr:
            errors.append(f"Missing XML entity: {entity}")

    # 4. Bracket balance
    for open_b, close_b in [('(', ')'), ('[', ']'), ('{', '}')]:
        src_balance = msgid.count(open_b) - msgid.count(close_b)
        dst_balance = msgstr.count(open_b) - msgstr.count(close_b)
        if src_balance != dst_balance:
            errors.append(f"Bracket imbalance '{open_b}{close_b}': src={src_balance} dst={dst_balance}")

    # 5. Leading/trailing whitespace should be preserved
    if msgid.startswith('\n') and not msgstr.startswith('\n'):
        errors.append("Missing leading newline")
    if msgid.endswith('\n') and not msgstr.endswith('\n'):
        errors.append("Missing trailing newline")

    # 6. Technical tokens that must NOT be translated
    for token in ['/mqtt', '/ki', '/api', '/telegram', '/help', '/bot',
                  'localhost', 'JSON', 'MQTT', 'XMPP', 'TLS', 'HTTPS',
                  'HTTP', 'QoS', 'ejabberd', 'Prosody', 'curl', 'POST',
                  'GET', 'Bearer', 'PEM', 'SHA-256', 'SCRAM', 'SOCKS5',
                  'DinoX', 'Node-RED', 'Home Assistant', 'Mosquitto',
                  'HiveMQ', 'OpenClaw', 'Ollama', 'GStreamer', 'nginx',
                  'CA', 'MAM', 'MUC', 'LWT']:
        if token in msgid and token not in msgstr:
            errors.append(f"Missing technical token: {token}")

    return len(errors) == 0, errors


# ─── German translations ────────────────────────────────────────────
DE = {
    # === Tor Manager ===
    "Tor": "Tor",
    "Tor Connection": "Tor-Verbindung",
    "Enable Integrated Tor": "Integriertes Tor aktivieren",
    "Starts a private Tor process for DinoX": "Startet einen privaten Tor-Prozess für DinoX",
    "Bridges (Censorship Circumvention)": "Brücken (Zensurumgehung)",
    "Required if Tor is blocked by your ISP or government.": "Erforderlich, wenn Tor von Ihrem ISP oder Ihrer Regierung blockiert wird.",
    "Use Bridges": "Brücken verwenden",
    "Hides the fact that you are using Tor.": "Verbirgt die Tatsache, dass Sie Tor verwenden.",
    "Firewall Mode (Port 80/443 Only)": "Firewall-Modus (nur Port 80/443)",
    "Only connect to bridges using standard web ports. Helps behind strict firewalls.": "Nur Brücken über Standard-Web-Ports verwenden. Hilft hinter strikten Firewalls.",
    "Warning: Only bridges on port 80/443 will work when Firewall Mode is enabled!": "Warnung: Bei aktiviertem Firewall-Modus funktionieren nur Brücken auf Port 80/443!",
    "Bridge List (Auto or Manual Entry)": "Brückenliste (automatisch oder manuell)",
    "Request Fresh Bridges": "Neue Brücken anfordern",
    "Connects to Tor Project (Moat) to fetch unblocked bridges.": "Verbindet sich mit dem Tor-Projekt (Moat), um nicht blockierte Brücken abzurufen.",
    "Request": "Anfordern",
    "Alternatively get bridges at https://bridges.torproject.org/": "Alternativ erhalten Sie Brücken unter https://bridges.torproject.org/",
    "Loading...": "Laden…",
    "Error fetching challenge": "Fehler beim Abrufen der Aufgabe",
    "OK": "OK",
    "Image Error": "Bildfehler",
    "Could not load CAPTCHA image.": "CAPTCHA-Bild konnte nicht geladen werden.",
    "Type characters from image...": "Zeichen aus dem Bild eingeben…",
    "Solve CAPTCHA": "CAPTCHA lösen",
    "Please type the characters you see in the image to receive bridges.": "Bitte geben Sie die Zeichen ein, die Sie im Bild sehen, um Brücken zu erhalten.",
    "Cancel": "Abbrechen",
    "Submit": "Absenden",
    "Received %d fresh bridges.": "Es wurden %d neue Brücken empfangen.",
    "Good news! We found %d bridges on common ports (443/80). These are prioritized.": "Gute Nachricht! Es wurden %d Brücken auf gängigen Ports (443/80) gefunden. Diese werden bevorzugt.",
    "Warning: None of the bridges use standard ports (443/80). If you are behind a strict firewall, you might need to try again.": "Warnung: Keine der Brücken verwendet Standard-Ports (443/80). Hinter einer strikten Firewall müssen Sie es eventuell erneut versuchen.",
    "Success": "Erfolg",
    "Try Again": "Erneut versuchen",
    "Failed": "Fehlgeschlagen",
    "No bridges received. Maybe the solution was wrong?": "Keine Brücken empfangen. Vielleicht war die Lösung falsch?",
    "Error": "Fehler",
    "Tor Network": "Tor-Netzwerk",
    "Checking status...": "Status wird geprüft…",
    "Enable Tor": "Tor aktivieren",
    "Network Settings": "Netzwerkeinstellungen",
    "Bootstrapping: %d%%": "Bootstrapping: %d%%",
    "Tor Starting: %d%%\n%s": "Tor startet: %d%%\n%s",
    "Bridges": "Brücken",
    "Direct": "Direkt",
    "Tor Connected (%s)": "Tor verbunden (%s)",
    "Connected (%s)": "Verbunden (%s)",
    "Tor Starting...": "Tor startet…",
    "Starting...": "Startet…",
    "Tor Disabled": "Tor deaktiviert",
    "Tor is disabled": "Tor ist deaktiviert",

    # === MQTT Settings & Bot Manager ===
    "MQTT (Standalone)": "MQTT (Eigenständig)",
    "Standalone MQTT Connection": "Eigenständige MQTT-Verbindung",
    "Global MQTT broker — independent of your XMPP accounts.\nFor account-specific MQTT, use Account Settings → MQTT Bot.": "Globaler MQTT-Broker — unabhängig von Ihren XMPP-Konten.\nFür kontospezifisches MQTT verwenden Sie Kontoeinstellungen → MQTT-Bot.",
    "Enable Standalone MQTT": "Eigenständiges MQTT aktivieren",
    "Connect to an external MQTT broker (Mosquitto, Home Assistant, HiveMQ…)": "Mit einem externen MQTT-Broker verbinden (Mosquitto, Home Assistant, HiveMQ…)",
    "Broker": "Broker",
    "Host": "Host",
    "Port": "Port",
    "TLS Encryption": "TLS-Verschlüsselung",
    "Enable for port 8883 or secure connections": "Für Port 8883 oder sichere Verbindungen aktivieren",
    "\u26a0 TLS Disabled": "\u26a0 TLS deaktiviert",
    "TLS Disabled": "TLS deaktiviert",
    "Credentials and data are sent in plain text to a non-local host!": "Anmeldedaten und Daten werden im Klartext an einen externen Host gesendet!",
    "Authentication": "Authentifizierung",
    "Leave empty if the broker requires no authentication.": "Leer lassen, wenn der Broker keine Authentifizierung erfordert.",
    "Username": "Benutzername",
    "Password": "Passwort",
    "MQTT Bot Manager": "MQTT-Bot-Manager",
    "Publish presets, alerts, bridges, free-text and more": "Veröffentlichungsvorlagen, Alarme, Brücken, Freitext und mehr",
    "Open Bot Manager": "Bot-Manager öffnen",
    "Configure publish presets, alert rules, bridge rules, free-text publishing": "Veröffentlichungsvorlagen, Alarmregeln, Brückenregeln, Freitext-Veröffentlichung konfigurieren",
    "Show Bot in Chat": "Bot im Chat anzeigen",
    "Re-open the MQTT Bot conversation if you closed it": "MQTT-Bot-Unterhaltung erneut öffnen, falls geschlossen",
    "Re-open the MQTT Bot conversation in the sidebar": "MQTT-Bot-Unterhaltung in der Seitenleiste erneut öffnen",
    "Home Assistant Discovery": "Home Assistant Discovery",
    "Announce DinoX as a device in Home Assistant via MQTT Discovery.\nRequires a broker with retained message support (not XMPP-MQTT).": "DinoX als Gerät in Home Assistant via MQTT Discovery ankündigen.\nErfordert einen Broker mit Retained-Message-Unterstützung (nicht XMPP-MQTT).",
    "Enable Discovery": "Discovery aktivieren",
    "Publish device and entity configs to the broker": "Geräte- und Entity-Konfigurationen an den Broker veröffentlichen",
    "Discovery Prefix": "Discovery-Präfix",
    "Connected": "Verbunden",
    "Connecting…": "Verbinde…",
    "Disabled": "Deaktiviert",
    "Not connected": "Nicht verbunden",
    "Save & Apply": "Speichern & Anwenden",
    "Reconnect": "Neu verbinden",
    "Disabled — enable first": "Deaktiviert — zuerst aktivieren",
    "No broker host configured": "Kein Broker-Host konfiguriert",
    "Reconnecting…": "Verbinde erneut…",
    "MQTT Bot — %s": "MQTT-Bot — %s",
    "MQTT Bot — Standalone": "MQTT-Bot — Eigenständig",
    "Connection": "Verbindung",
    "Enable MQTT": "MQTT aktivieren",
    "Activate the MQTT client for this account": "MQTT-Client für dieses Konto aktivieren",
    "Connection Mode": "Verbindungsmodus",
    "How this account connects to MQTT": "Wie dieses Konto sich mit MQTT verbindet",
    "XMPP Server (ejabberd / Prosody)": "XMPP-Server (ejabberd / Prosody)",
    "Custom Broker (any MQTT server)": "Eigener Broker (beliebiger MQTT-Server)",
    "Status": "Status",
    "Disconnected": "Getrennt",
    "XMPP Server MQTT": "XMPP-Server-MQTT",
    "Uses your XMPP server's built-in MQTT.\nNote: ejabberd/Prosody MQTT is still in testing.": "Nutzt das integrierte MQTT Ihres XMPP-Servers.\nHinweis: MQTT bei ejabberd/Prosody ist noch in der Testphase.",
    "Detected Server": "Erkannter Server",
    "unknown": "unbekannt",
    "Auto-detected from account domain (%s)": "Automatisch erkannt von Kontodomain (%s)",
    "Use XMPP Credentials": "XMPP-Anmeldedaten verwenden",
    "Share your XMPP login with ejabberd's MQTT (recommended)": "XMPP-Anmeldedaten für ejabberd-MQTT freigeben (empfohlen)",
    "MQTT Port": "MQTT-Port",
    "ejabberd mod_mqtt usually runs on port 8883 with TLS": "ejabberd mod_mqtt läuft normalerweise auf Port 8883 mit TLS",
    "Custom Broker": "Eigener Broker",
    "Connect to any MQTT broker with own credentials.": "Mit beliebigem MQTT-Broker und eigenen Anmeldedaten verbinden.",
    "Hostname": "Hostname",
    "Credentials for the custom MQTT broker.": "Anmeldedaten für den eigenen MQTT-Broker.",
    "MQTT Username": "MQTT-Benutzername",
    "MQTT Password": "MQTT-Passwort",
    "Disconnect and reconnect to the MQTT broker": "Verbindung zum MQTT-Broker trennen und neu verbinden",
    "Standalone MQTT": "Eigenständiges MQTT",
    "Connection settings are managed in Preferences → MQTT (Standalone).": "Verbindungseinstellungen werden unter Einstellungen → MQTT (Eigenständig) verwaltet.",
    "No broker configured — set in Preferences": "Kein Broker konfiguriert — in Einstellungen festlegen",
    "Configuration": "Konfiguration",
    "Topic Subscriptions": "Themen-Abonnements",
    "Manage subscribed MQTT topics": "Abonnierte MQTT-Themen verwalten",
    "Publish &amp; Free Text": "Veröffentlichen &amp; Freitext",
    "Publish presets and free-text publishing": "Veröffentlichungsvorlagen und Freitext-Veröffentlichung",
    "Alert Rules": "Alarmregeln",
    "Notification rules for MQTT messages": "Benachrichtigungsregeln für MQTT-Nachrichten",
    "Bridge Rules": "Brückenregeln",
    "Forward MQTT messages to XMPP contacts": "MQTT-Nachrichten an XMPP-Kontakte weiterleiten",
    "Runtime": "Laufzeit",
    "Pause Messages": "Nachrichten pausieren",
    "Paused — messages are recorded but not shown": "Pausiert — Nachrichten werden aufgezeichnet, aber nicht angezeigt",
    "Incoming MQTT messages are recorded but not shown in chat": "Eingehende MQTT-Nachrichten werden aufgezeichnet, aber nicht im Chat angezeigt",
    "Messages paused": "Nachrichten pausiert",
    "Messages resumed": "Nachrichten fortgesetzt",
    "Auto-announce DinoX as a device in HA.": "DinoX automatisch als Gerät in HA ankündigen.",
    "Publish device &amp; entity configs via MQTT": "Geräte- &amp; Entity-Konfigurationen via MQTT veröffentlichen",
    "Subscribe": "Abonnieren",
    "Bridge": "Brücke",
    "Add Alert": "Alarm hinzufügen",
    "Add Preset": "Vorlage hinzufügen",
    "Unsubscribe": "Abbestellen",

    # === Topic Manager ===
    "MQTT Topics — %s": "MQTT-Themen — %s",
    "MQTT Topic Manager": "MQTT-Themen-Manager",
    "Active MQTT topic subscriptions with QoS level": "Aktive MQTT-Themenabonnements mit QoS-Stufe",
    "MQTT → XMPP Bridge": "MQTT → XMPP-Brücke",
    "Forward MQTT messages to XMPP contacts or MUCs": "MQTT-Nachrichten an XMPP-Kontakte oder MUCs weiterleiten",
    "Threshold alerts for MQTT topics": "Schwellenwertalarme für MQTT-Themen",
    "Active": "Aktiv",
    "Remove bridge": "Brücke entfernen",
    "Remove alert": "Alarm entfernen",

    # === Alert Manager ===
    "Silent (no notification)": "Stumm (keine Benachrichtigung)",
    "Normal (badge)": "Normal (Abzeichen)",
    "Alert (badge + notification)": "Alarm (Abzeichen + Benachrichtigung)",
    "Critical (badge + notification + sound)": "Kritisch (Abzeichen + Benachrichtigung + Ton)",
    "Normal": "Normal",

    # === Discovery Manager ===
    "Subscriptions": "Abonnements",
    "Alerts Pause": "Alarme-Pause",
    "Refresh Discovery": "Discovery aktualisieren",
    "auto": "auto",
    "connected": "verbunden",
    "disconnected": "getrennt",
    "unconfigured": "nicht konfiguriert",
    "MQTT Discovery Status\n": "MQTT-Discovery-Status\n",
    "Format: Device Discovery (HA 2024.x+)\n": "Format: Geräte-Discovery (HA 2024.x+)\n",
    "Enabled: %s\n": "Aktiviert: %s\n",
    "Yes": "Ja",
    "No": "Nein",

    # === Server Detector ===
    "ejabberd (mod_mqtt)": "ejabberd (mod_mqtt)",
    "Prosody (mod_pubsub_mqtt)": "Prosody (mod_pubsub_mqtt)",
    "Standalone Broker": "Eigenständiger Broker",
    "Unknown": "Unbekannt",
    "Service Discovery module not available": "Service-Discovery-Modul nicht verfügbar",
    "No MQTT server type detected — configure manually": "Kein MQTT-Servertyp erkannt — manuell konfigurieren",

    # === Bot Conversation ===
    "(empty)": "(leer)",

    # === MQTT Command Handler / Plugin (chat bot responses) ===
    "MQTT Status\n": "MQTT-Status\n",
    "MQTT Connection Config\n": "MQTT-Verbindungskonfiguration\n",
    "Connected \u2714": "Verbunden \u2714",
    "Disconnected \u2718": "Getrennt \u2718",
    "Connection Status": "Verbindungsstatus",
    "Disabled — enable in Preferences first": "Deaktiviert — zuerst in Einstellungen aktivieren",
    "No active MQTT connections.\n": "Keine aktiven MQTT-Verbindungen.\n",
    "Account %s: %s\n": "Konto %s: %s\n",
    "Standalone: %s\n": "Eigenständig: %s\n",
    "Connection: %s\n": "Verbindung: %s\n",
    "Broker: %s:%d\n": "Broker: %s:%d\n",
    "TLS: %s\n": "TLS: %s\n",
    "Auth: %s (manual)\n": "Auth: %s (manuell)\n",
    "Auth: None\n": "Auth: Keine\n",
    "Auth: XMPP Credentials (shared)\n": "Auth: XMPP-Anmeldedaten (geteilt)\n",
    "Client: %s\n\n": "Client: %s\n\n",
    "Topics: %d subscribed\n": "Themen: %d abonniert\n",
    "Active Subscriptions\n": "Aktive Abonnements\n",
    "Active Topic Subscriptions\n": "Aktive Themenabonnements\n",
    "Active subscriptions have been updated.": "Aktive Abonnements wurden aktualisiert.",
    "No topic subscriptions configured.\n\nUse /mqtt subscribe <topic> to add one.": "Keine Themenabonnements konfiguriert.\n\nVerwenden Sie /mqtt subscribe <topic>, um eines hinzuzufügen.",
    "Subscribed to: %s \u2714": "Abonniert: %s \u2714",
    "Already subscribed to: %s": "Bereits abonniert: %s",
    "Unsubscribed from: %s \u2714": "Abbestellt: %s \u2714",
    "Topic not found in subscriptions: %s": "Thema nicht in Abonnements gefunden: %s",
    "Published to %s:\n%s": "Veröffentlicht an %s:\n%s",
    "Cannot publish — MQTT client is not connected.": "Veröffentlichung nicht möglich — MQTT-Client ist nicht verbunden.",
    "Type /mqtt help for available commands.": "Geben Sie /mqtt help ein für verfügbare Befehle.",
    "No config available for this connection.": "Keine Konfiguration für diese Verbindung verfügbar.",
    "Server Type: %s\n": "Servertyp: %s\n",
    "Reconnecting %s…\n\nCheck /mqtt status in a few seconds.": "Neuverbindung %s…\n\nPrüfen Sie /mqtt status in einigen Sekunden.",
    "Reconnecting standalone connection…\n\nCheck /mqtt status in a few seconds.": "Eigenständige Verbindung wird neu aufgebaut…\n\nPrüfen Sie /mqtt status in einigen Sekunden.",
    "Reconnecting to %s...": "Verbinde erneut mit %s...",
    "Connection '%s' is disabled. Enable it first.": "Verbindung '%s' ist deaktiviert. Aktivieren Sie sie zuerst.",
    "Opening Topic Manager…": "Themen-Manager wird geöffnet…",
    "Alert manager not available.": "Alarm-Manager nicht verfügbar.",
    "Bridge manager not available.": "Brücken-Manager nicht verfügbar.",
    "MQTT database not available.": "MQTT-Datenbank nicht verfügbar.",
    "MQTT is not yet enabled for %s.\n": "MQTT ist noch nicht aktiviert für %s.\n",
    "To enable it, go to:\n  Account Settings → MQTT Bot → Enable MQTT\n\nOr type: /mqtt help": "Zum Aktivieren gehen Sie zu:\n  Kontoeinstellungen → MQTT-Bot → MQTT aktivieren\n\nOder geben Sie ein: /mqtt help",
    "MQTT Bot connected for %s \u2714\n\n": "MQTT-Bot verbunden für %s \u2714\n\n",
    "MQTT Bot connected \u2714\n\nType /mqtt help for available commands.\nSubscribed MQTT messages will appear here.": "MQTT-Bot verbunden \u2714\n\nGeben Sie /mqtt help für verfügbare Befehle ein.\nAbonnierte MQTT-Nachrichten erscheinen hier.",
    "Unknown command: /mqtt %s\n\nType /mqtt help for available commands.": "Unbekannter Befehl: /mqtt %s\n\nGeben Sie /mqtt help für verfügbare Befehle ein.",
    "Not enough parameters.": "Nicht genügend Parameter.",

    # Publish presets
    "Publish Presets": "Veröffentlichungsvorlagen",
    "Publish Presets\n": "Veröffentlichungsvorlagen\n",
    "No publish presets": "Keine Veröffentlichungsvorlagen",
    "No publish presets defined.\n\nUse /mqtt preset add <name> <topic> <payload> to create one.\n\nExample:\n  /mqtt preset add LichtAN home/light/set ON": "Keine Veröffentlichungsvorlagen definiert.\n\nVerwenden Sie /mqtt preset add <name> <topic> <payload>, um eine zu erstellen.\n\nBeispiel:\n  /mqtt preset add LichtAN home/light/set ON",
    "Preset '%s' created \u2714\n\nTopic: %s\nPayload: %s\n\nUse /mqtt preset %s to publish.": "Vorlage '%s' erstellt \u2714\n\nThema: %s\nNutzlast: %s\n\nVerwenden Sie /mqtt preset %s zum Veröffentlichen.",
    "Preset '%s' already exists. Remove it first with /mqtt preset remove <N>.": "Vorlage '%s' existiert bereits. Entfernen Sie sie zuerst mit /mqtt preset remove <N>.",
    "Preset '%s' not found.\n\nUse /mqtt presets to list available presets.": "Vorlage '%s' nicht gefunden.\n\nVerwenden Sie /mqtt presets, um verfügbare Vorlagen aufzulisten.",
    "Preset #%d not found. Use /mqtt presets to see numbers.": "Vorlage #%d nicht gefunden. Verwenden Sie /mqtt presets, um Nummern anzuzeigen.",
    "Preset '%s' (#%d) removed \u2714": "Vorlage '%s' (#%d) entfernt \u2714",
    "Published: %s → %s : %s \u2714": "Veröffentlicht: %s → %s : %s \u2714",
    "Quick-publish actions for the MQTT bot": "Schnellveröffentlichungs-Aktionen für den MQTT-Bot",
    "Remove this preset": "Diese Vorlage entfernen",
    "Add Bridge": "Brücke hinzufügen",
    "Use the form below to add a preset": "Verwenden Sie das Formular unten, um eine Vorlage hinzuzufügen",

    # Alert rules
    "Alert Rules\n": "Alarmregeln\n",
    "No alert rules configured": "Keine Alarmregeln konfiguriert",
    "No alert rules defined.\n\nUse /mqtt alert <topic> <op> <value> to create one.": "Keine Alarmregeln definiert.\n\nVerwenden Sie /mqtt alert <topic> <op> <value>, um eine zu erstellen.",
    "Alert rule created \u2714\n\n": "Alarmregel erstellt \u2714\n\n",
    "Alert rule #%d removed \u2714": "Alarmregel #%d entfernt \u2714",
    "Alert rule #%d not found.\n\nUse /mqtt alerts to see rule numbers.": "Alarmregel #%d nicht gefunden.\n\nVerwenden Sie /mqtt alerts, um Regelnummern anzuzeigen.",
    "Rules that trigger notifications when MQTT messages match patterns": "Regeln, die Benachrichtigungen auslösen, wenn MQTT-Nachrichten Muster entsprechen",
    "New Alert Rule": "Neue Alarmregel",
    "New Bridge Rule": "Neue Brückenregel",
    "Trigger a notification when an MQTT message matches": "Benachrichtigung auslösen, wenn eine MQTT-Nachricht übereinstimmt",
    "MQTT messages matching this topic will be forwarded\nas XMPP chat messages to the target contact.": "MQTT-Nachrichten zu diesem Thema werden\nals XMPP-Chatnachrichten an den Zielkontakt weitergeleitet.",
    "Forward MQTT messages to an XMPP contact or MUC": "MQTT-Nachrichten an einen XMPP-Kontakt oder MUC weiterleiten",

    # Bridge rules
    "Bridge Rules\n": "Brückenregeln\n",
    "MQTT → XMPP Bridge Rules\n": "MQTT → XMPP-Brückenregeln\n",
    "No bridge rules configured": "Keine Brückenregeln konfiguriert",
    "Bridge rule created \u2714\n\nTopic: %s\n": "Brückenregel erstellt \u2714\n\nThema: %s\n",
    "Bridge rule #%d removed \u2714": "Brückenregel #%d entfernt \u2714",
    "Bridge rule #%d not found.\n\nUse /mqtt bridges to see rule numbers.": "Brückenregel #%d nicht gefunden.\n\nVerwenden Sie /mqtt bridges, um Regelnummern anzuzeigen.",
    "No bridge rules for this connection (%s).\n\nUse /mqtt bridge <topic> <jid> to create one.": "Keine Brückenregeln für diese Verbindung (%s).\n\nVerwenden Sie /mqtt bridge <topic> <jid>, um eine zu erstellen.",

    # Topic aliases
    "Topic Aliases\n": "Themen-Aliase\n",
    "Alias set: %s → %s \u2714": "Alias gesetzt: %s → %s \u2714",
    "Alias removed for: %s \u2714": "Alias entfernt für: %s \u2714",
    "No alias found for: %s": "Kein Alias gefunden für: %s",
    "No topic aliases configured.\n\nUse /mqtt alias <topic> <name> to set one.": "Keine Themen-Aliase konfiguriert.\n\nVerwenden Sie /mqtt alias <topic> <name>, um einen zu setzen.",
    "Alias (optional, e.g. 🌡 Living Room)": "Alias (optional, z. B. 🌡 Wohnzimmer)",

    # QoS
    "Topic QoS Settings\n": "Themen-QoS-Einstellungen\n",
    "Quality of Service level": "Quality-of-Service-Stufe",
    "at most once": "höchstens einmal",
    "at least once": "mindestens einmal",
    "exactly once": "genau einmal",
    "Topic '%s' QoS set to %d (%s) \u2714\n\n": "Thema '%s' QoS auf %d (%s) gesetzt \u2714\n\n",
    "Topic '%s' QoS reset to default (0 — at most once) \u2714": "Thema '%s' QoS auf Standard zurückgesetzt (0 — höchstens einmal) \u2714",
    "Topic '%s' QoS: %d (%s)\n\n": "Thema '%s' QoS: %d (%s)\n\n",

    # Priority
    "Priority": "Priorität",
    "Topic Priority Overrides\n": "Themen-Prioritätsüberschreibungen\n",
    "Topic '%s' priority set to %s \u2714": "Thema '%s' Priorität auf %s gesetzt \u2714",
    "Topic '%s' reset to default priority (normal) \u2714": "Thema '%s' auf Standardpriorität (normal) zurückgesetzt \u2714",
    "Notification priority": "Benachrichtigungspriorität",

    # History/Charts
    "Topics with History\n": "Themen mit Verlauf\n",
    "Topics with History Data\n": "Themen mit Verlaufsdaten\n",
    "No topic history available yet.\nHistory is recorded when MQTT messages arrive.": "Noch kein Themenverlauf verfügbar.\nDer Verlauf wird aufgezeichnet, wenn MQTT-Nachrichten eintreffen.",
    "No history for topic: %s": "Kein Verlauf für Thema: %s",
    "Cannot generate chart for '%s'.\n\n": "Diagramm für '%s' kann nicht erstellt werden.\n\n",
    "No topic history available.\nHistory is recorded when MQTT messages arrive.\n\nUsage: /mqtt chart <topic> [N]": "Kein Themenverlauf verfügbar.\nDer Verlauf wird aufgezeichnet, wenn MQTT-Nachrichten eintreffen.\n\nVerwendung: /mqtt chart <topic> [N]",
    "Possible reasons:\n\u2022 No history data for this topic\n\u2022 Payload is not numeric (need numbers or JSON with numeric fields)\n\u2022 Less than 2 data points available": "Mögliche Gründe:\n\u2022 Keine Verlaufsdaten für dieses Thema\n\u2022 Nutzlast ist nicht numerisch (Zahlen oder JSON mit numerischen Feldern erforderlich)\n\u2022 Weniger als 2 Datenpunkte verfügbar",
    "History: %s\n": "Verlauf: %s\n",
    "History: %s (DB)\n": "Verlauf: %s (DB)\n",

    # DB Stats
    "mqtt.db Statistics\n": "mqtt.db-Statistiken\n",
    "Messages:       %d rows (max %d days)\n": "Nachrichten:    %d Zeilen (max. %d Tage)\n",
    "Freetext:       %d rows (max %d days)\n": "Freitext:       %d Zeilen (max. %d Tage)\n",
    "Connection Log: %d rows (max %d days)\n": "Verbindungslog: %d Zeilen (max. %d Tage)\n",
    "Alert Rules:    %d rows (user-managed)\n": "Alarmregeln:    %d Zeilen (benutzerverwalt.)\n",
    "Bridge Rules:   %d rows (user-managed)\n": "Brückenregeln:  %d Zeilen (benutzerverwalt.)\n",
    "Publish Presets:%d rows (user-managed)\n": "Vorlagen:       %d Zeilen (benutzerverwalt.)\n",
    "Publish History:%d rows (max %d days)\n": "Veröff.-Verlauf:%d Zeilen (max. %d Tage)\n",
    "Retained Cache: %d rows (permanent)\n": "Retained-Cache: %d Zeilen (permanent)\n",
    "Topic Stats:    %d rows (permanent)\n": "Themenstatistik:%d Zeilen (permanent)\n",

    # Purge
    "Purge complete: %d expired rows deleted \u2714": "Bereinigung abgeschlossen: %d abgelaufene Zeilen gelöscht \u2714",
    "No expired data found. All data is within retention limits:\n\u2022 Messages: %d days\n": "Keine abgelaufenen Daten gefunden. Alle Daten sind innerhalb der Aufbewahrungsfristen:\n\u2022 Nachrichten: %d Tage\n",
    "\u2022 Connection Log: %d days\n": "\u2022 Verbindungslog: %d Tage\n",
    "\u2022 Freetext: %d days\n": "\u2022 Freitext: %d Tage\n",
    "\u2022 Publish History: %d days": "\u2022 Veröffentlichungsverlauf: %d Tage",

    # Pause/Resume
    "MQTT messages paused \u23f8\n\nMessages are still recorded in history.\nUse /mqtt resume to resume display.": "MQTT-Nachrichten pausiert \u23f8\n\nNachrichten werden weiterhin im Verlauf aufgezeichnet.\nVerwenden Sie /mqtt resume, um die Anzeige fortzusetzen.",
    "MQTT messages resumed \u25b6\n\nIncoming messages will appear as chat bubbles again.": "MQTT-Nachrichten fortgesetzt \u25b6\n\nEingehende Nachrichten werden wieder als Chat-Blasen angezeigt.",
    "Messages are already paused.\nUse /mqtt resume to resume.": "Nachrichten sind bereits pausiert.\nVerwenden Sie /mqtt resume zum Fortsetzen.",
    "Messages are not paused.": "Nachrichten sind nicht pausiert.",

    # Discovery
    "HA Discovery enabled (prefix: %s).\n\nReconnecting to set LWT… check /mqtt status in a few seconds.": "HA Discovery aktiviert (Präfix: %s).\n\nVerbinde neu für LWT… prüfen Sie /mqtt status in einigen Sekunden.",
    "HA Discovery already enabled — re-published configs.": "HA Discovery bereits aktiviert — Konfigurationen erneut veröffentlicht.",
    "HA Discovery disabled — configs removed from broker.\n\nHome Assistant will remove the device after its availability timeout.": "HA Discovery deaktiviert — Konfigurationen vom Broker entfernt.\n\nHome Assistant wird das Gerät nach dem Verfügbarkeits-Timeout entfernen.",
    "HA Discovery is already disabled.": "HA Discovery ist bereits deaktiviert.",
    "HA Discovery is disabled for '%s'.\n\nUse /mqtt discovery on to enable.": "HA Discovery ist deaktiviert für '%s'.\n\nVerwenden Sie /mqtt discovery on zum Aktivieren.",
    "HA Discovery is enabled (prefix: %s) but not yet connected.": "HA Discovery ist aktiviert (Präfix: %s), aber noch nicht verbunden.",
    "HA Discovery is not active. Enable it first with /mqtt discovery on": "HA Discovery ist nicht aktiv. Aktivieren Sie es zuerst mit /mqtt discovery on",
    "Published updated state for all entities.": "Aktualisierter Status für alle Entitäten veröffentlicht.",
    "Current prefix: %s\n\nTo change, edit the Discovery Prefix in Settings.": "Aktueller Präfix: %s\n\nZum Ändern bearbeiten Sie den Discovery-Präfix in den Einstellungen.",
    "Announced Entities:\n": "Angekündigte Entitäten:\n",
    "Config topic: %s/device/%s/config\n": "Konfig-Topic: %s/device/%s/config\n",
    "Node ID: %s\n": "Node-ID: %s\n",
    "HA status topic: %s\n": "HA-Status-Topic: %s\n",
    "Availability: %s\n": "Verfügbarkeit: %s\n",

    # Validation messages
    "Invalid QoS level: %s\n\nValid values: 0, 1, 2": "Ungültige QoS-Stufe: %s\n\nGültige Werte: 0, 1, 2",
    "Invalid JID: %s\n\n%s": "Ungültige JID: %s\n\n%s",
    "Unknown operator: %s\n\nValid operators: > < >= <= == != contains": "Unbekannter Operator: %s\n\nGültige Operatoren: > < >= <= == != contains",
    "Invalid number: %s": "Ungültige Zahl: %s",
    "Invalid port: %s": "Ungültiger Port: %s",
    "Invalid mode: %s": "Ungültiger Modus: %s",
    "Allowed: 1024-65535": "Erlaubt: 1024-65535",

    # Usage strings (keep commands untranslated, translate descriptions)
    "Usage: /mqtt subscribe <topic>\n\nExamples:\n  /mqtt subscribe home/sensors/#\n  /mqtt subscribe home/+/temperature": "Verwendung: /mqtt subscribe <topic>\n\nBeispiele:\n  /mqtt subscribe home/sensors/#\n  /mqtt subscribe home/+/temperature",
    "Usage: /mqtt unsubscribe <topic>": "Verwendung: /mqtt unsubscribe <topic>",
    "Usage: /mqtt publish <topic> <payload>\n\nExample:\n  /mqtt publish home/light/set ON": "Verwendung: /mqtt publish <topic> <payload>\n\nBeispiel:\n  /mqtt publish home/light/set ON",
    "Usage: /mqtt publish <topic> <payload>\n\nPayload cannot be empty.": "Verwendung: /mqtt publish <topic> <payload>\n\nNutzlast darf nicht leer sein.",
    "Usage: /mqtt preset add <name> <topic> <payload>": "Verwendung: /mqtt preset add <name> <topic> <payload>",
    "Usage: /mqtt preset add <name> <topic> <payload>\n\nExample:\n  /mqtt preset add LichtAN home/light/set ON\n  /mqtt preset add TempRead home/sensor/get read": "Verwendung: /mqtt preset add <name> <topic> <payload>\n\nBeispiel:\n  /mqtt preset add LichtAN home/light/set ON\n  /mqtt preset add TempRead home/sensor/get read",
    "Usage: /mqtt preset remove <number>\n\nUse /mqtt presets to see numbers.": "Verwendung: /mqtt preset remove <number>\n\nVerwenden Sie /mqtt presets, um Nummern anzuzeigen.",
    "Usage: /mqtt qos <topic> <0|1|2>": "Verwendung: /mqtt qos <topic> <0|1|2>",
    "Usage: /mqtt rmalert <number>\n\nUse /mqtt alerts to see rule numbers.": "Verwendung: /mqtt rmalert <number>\n\nVerwenden Sie /mqtt alerts, um Regelnummern anzuzeigen.",
    "Usage: /mqtt rmalias <topic>": "Verwendung: /mqtt rmalias <topic>",
    "Usage: /mqtt rmbridge <number>\n\nUse /mqtt bridges to see rule numbers.": "Verwendung: /mqtt rmbridge <number>\n\nVerwenden Sie /mqtt bridges, um Regelnummern anzuzeigen.",
    "Usage: /mqtt alias <topic> <name>\n\nAlias name cannot be empty.": "Verwendung: /mqtt alias <topic> <name>\n\nAlias-Name darf nicht leer sein.",
    "Usage: /mqtt alias <topic> <name>\n\nExample:\n  /mqtt alias home/sensors/temp 🌡 Wohnzimmer": "Verwendung: /mqtt alias <topic> <name>\n\nBeispiel:\n  /mqtt alias home/sensors/temp 🌡 Wohnzimmer",
    "Usage: /mqtt bridge <topic> <jid>\n\nForward MQTT messages to an XMPP contact.\n\nExamples:\n  /mqtt bridge home/alerts/# user@example.com\n  /mqtt bridge sensors/fire admin@company.org": "Verwendung: /mqtt bridge <topic> <jid>\n\nMQTT-Nachrichten an einen XMPP-Kontakt weiterleiten.\n\nBeispiele:\n  /mqtt bridge home/alerts/# user@example.com\n  /mqtt bridge sensors/fire admin@company.org",
    "Usage: /mqtt priority <topic> <level>\n\nLevels: silent, normal, alert, critical\n\nExamples:\n  /mqtt priority home/sensors/heartbeat silent\n  /mqtt priority home/alerts/# critical": "Verwendung: /mqtt priority <topic> <level>\n\nStufen: silent, normal, alert, critical\n\nBeispiele:\n  /mqtt priority home/sensors/heartbeat silent\n  /mqtt priority home/alerts/# critical",
    "Usage: /mqtt discovery [on|off|refresh]\n\n  on      — Enable HA Discovery & publish configs\n  off     — Disable & remove from broker\n  refresh — Re-publish state values": "Verwendung: /mqtt discovery [on|off|refresh]\n\n  on      — HA Discovery aktivieren & Konfig veröffentlichen\n  off     — Deaktivieren & vom Broker entfernen\n  refresh — Statuswerte erneut veröffentlichen",
    "Usage: /mqtt alert <topic> <op> <value>\n\nOperators: > < >= <= == != contains\n\nExamples:\n  /mqtt alert home/temp > 30\n  /mqtt alert home/sensors/# contains error\n  /mqtt alert home/data.temperature > 25\n    (checks JSON field 'temperature')": "Verwendung: /mqtt alert <topic> <op> <value>\n\nOperatoren: > < >= <= == != contains\n\nBeispiele:\n  /mqtt alert home/temp > 30\n  /mqtt alert home/sensors/# contains error\n  /mqtt alert home/data.temperature > 25\n    (prüft JSON-Feld 'temperature')",

    # Hint strings
    "\nUse /mqtt chart <topic> [N] to generate a chart.": "\nVerwenden Sie /mqtt chart <topic> [N], um ein Diagramm zu erstellen.",
    "\nUse /mqtt history <topic> [N] to see values.": "\nVerwenden Sie /mqtt history <topic> [N], um Werte anzuzeigen.",
    "\nUse /mqtt preset <name> to publish.": "\nVerwenden Sie /mqtt preset <name> zum Veröffentlichen.",
    "\nUse /mqtt preset remove <number> to delete.": "\nVerwenden Sie /mqtt preset remove <number> zum Löschen.",
    "\nUse /mqtt priority <topic> normal to remove override.": "\nVerwenden Sie /mqtt priority <topic> normal, um die Überschreibung zu entfernen.",
    "\nUse /mqtt qos <topic> 0 to reset to default.": "\nVerwenden Sie /mqtt qos <topic> 0, um auf Standard zurückzusetzen.",
    "\nUse /mqtt rmalert <number> to remove a rule.": "\nVerwenden Sie /mqtt rmalert <number>, um eine Regel zu entfernen.",
    "\nUse /mqtt rmbridge <number> to remove a rule.": "\nVerwenden Sie /mqtt rmbridge <number>, um eine Regel zu entfernen.",
    "\nFree Text Publish: Enabled\n": "\nFreitext-Veröffentlichung: Aktiviert\n",
    "I only understand /mqtt commands.\n\nType /mqtt help for available commands.\nTo enable free-text publishing, configure it in\nAccount Settings → MQTT Bot → Publish &amp; Free Text.": "Ich verstehe nur /mqtt-Befehle.\n\nGeben Sie /mqtt help für verfügbare Befehle ein.\nUm Freitext-Veröffentlichung zu aktivieren, konfigurieren Sie dies in\nKontoeinstellungen → MQTT-Bot → Veröffentlichen &amp; Freitext.",

    # Free text / Publish
    "Publish Topic": "Veröffentlichungsthema",
    "Response Topic": "Antwortthema",
    "Payload": "Nutzlast",
    "  Publish Topic: %s\n": "  Veröffentlichungsthema: %s\n",
    "  Response Topic: %s\n": "  Antwortthema: %s\n",
    "Enable Free-Text Publish": "Freitext-Veröffentlichung aktivieren",
    "Type free text in the bot chat to publish directly to a topic": "Geben Sie Freitext im Bot-Chat ein, um direkt an ein Thema zu veröffentlichen",
    "Free-Text Publish (Node-RED)": "Freitext-Veröffentlichung (Node-RED)",
    "\u2192 Published to: %s": "\u2192 Veröffentlicht an: %s",

    # Form fields
    "Topic pattern": "Themenmuster",
    "Operator": "Operator",
    "Threshold / keyword": "Schwellenwert / Schlüsselwort",
    "Condition: %s %s\n": "Bedingung: %s %s\n",
    "Topic: %s\n": "Thema: %s\n",
    "Target: %s\n": "Ziel: %s\n",
    "Field: %s\n": "Feld: %s\n",
    "Origin: %s %s\n": "Quelle: %s %s\n",
    "Priority: %s\n": "Priorität: %s\n",
    "Prefix: %s\n": "Präfix: %s\n",
    "Cooldown: %llds": "Abklingzeit: %llds",
    "Status: %s": "Status: %s",
    "Status: %s\n": "Status: %s\n",
    "Status: No client\n": "Status: Kein Client\n",
    "Status:": "Status:",
    "Mode": "Modus",
    "Subscribe to Topic": "Thema abonnieren",
    "Subscription": "Abonnement",
    "Topics": "Themen",
    "Topics:": "Themen:",
    "Edit": "Bearbeiten",
    "Edit subscription": "Abonnement bearbeiten",
    "Moderator": "Moderator",
    "Make Moderator": "Zum Moderator machen",
    "Revoke Moderator": "Moderator entziehen",
    "Participant": "Teilnehmer",
    "Visitor": "Besucher",
    "Outcast": "Ausgeschlossen",
    "Your Affiliation": "Ihre Zugehörigkeit",
    "Your Role": "Ihre Rolle",
    "JID": "JID",
    "XMPP JID": "XMPP-JID",
    "No topics subscribed": "Keine Themen abonniert",
    "Mutual": "Gegenseitig",
    "From (they see you, you don't see them)": "Von (sie sehen Sie, Sie sehen sie nicht)",
    "To (you see them, they don't see you)": "An (Sie sehen sie, sie sehen Sie nicht)",
    "JSON field (optional)": "JSON-Feld (optional)",
    "Avatar": "Avatar",
    "Change Avatar": "Avatar ändern",
    "Remove Avatar": "Avatar entfernen",
    "Select Avatar": "Avatar auswählen",
    "Overview": "Übersicht",
    "Commands": "Befehle",
    "Commands:": "Befehle:",
    "Format": "Format",

    # No per-topic overrides
    "No per-topic QoS overrides set.\nAll topics use default QoS: 0 (at most once)\n\nUsage: /mqtt qos <topic> <0|1|2>\n\nQoS levels:\n  0 = At most once (fire & forget)\n  1 = At least once (acknowledged)\n  2 = Exactly once (guaranteed)": "Keine themenspezifischen QoS-Überschreibungen gesetzt.\nAlle Themen verwenden Standard-QoS: 0 (höchstens einmal)\n\nVerwendung: /mqtt qos <topic> <0|1|2>\n\nQoS-Stufen:\n  0 = Höchstens einmal (fire & forget)\n  1 = Mindestens einmal (bestätigt)\n  2 = Genau einmal (garantiert)",
    "No per-topic priority overrides set.\nAll topics use default priority: normal\n\nUsage: /mqtt priority <topic> <level>\nLevels: silent, normal, alert, critical": "Keine themenspezifischen Prioritätsüberschreibungen gesetzt.\nAlle Themen verwenden Standardpriorität: normal\n\nVerwendung: /mqtt priority <topic> <level>\nStufen: silent, normal, alert, critical",

    # Main app strings (non-plugin)
    "Use account:": "Konto verwenden:",
    "Record video message": "Videonachricht aufnehmen",
    "Set Status": "Status setzen",
    "Server Certificate": "Serverzertifikat",
    "TLS certificate used by the XMPP server": "TLS-Zertifikat des XMPP-Servers",
    "Issued by": "Ausgestellt von",
    "SHA-256 Fingerprint": "SHA-256-Fingerabdruck",
    "Remove Pinned Certificate": "Angeheftetes Zertifikat entfernen",
    "Postal Code": "Postleitzahl",
    "Proxy Type": "Proxy-Typ",
    "SOCKS5": "SOCKS5",
    "Proxy Hostname": "Proxy-Hostname",
    "Proxy Port": "Proxy-Port",
    "MITM Protection": "MITM-Schutz",
    "Require channel binding (SCRAM-*-PLUS). Rejects login if server does not support it.": "Channel-Binding (SCRAM-*-PLUS) erzwingen. Anmeldung wird abgelehnt, wenn der Server es nicht unterstützt.",
    "Botmother": "Botmother",
    "Manage Botmothers": "Botmothers verwalten",
    "Create, configure and delete Botmothers for this account": "Botmothers für dieses Konto erstellen, konfigurieren und löschen",
    "MQTT Bot (Account)": "MQTT-Bot (Konto)",
    "Manage Account MQTT Bot": "Konto-MQTT-Bot verwalten",
    "Topics, Publish Presets, Alerts and Bridges for this account's MQTT connection (separate from Standalone MQTT)": "Themen, Veröffentlichungsvorlagen, Alarme und Brücken für die MQTT-Verbindung dieses Kontos (getrennt vom eigenständigen MQTT)",
    "Enable Botmother": "Botmother aktivieren",
    "Start the local Botmother API server for managing XMPP bots": "Lokalen Botmother-API-Server zum Verwalten von XMPP-Bots starten",
    "API Server Mode": "API-Servermodus",
    "Local: localhost only. Network: all interfaces with TLS (HTTPS)": "Lokal: nur localhost. Netzwerk: alle Schnittstellen mit TLS (HTTPS)",
    "API Port": "API-Port",
    "Port for the HTTP(S) API server": "Port für den HTTP(S)-API-Server",
    "TLS Certificate (PEM)": "TLS-Zertifikat (PEM)",
    "TLS Private Key (PEM)": "Privater TLS-Schlüssel (PEM)",
    "Renew Self-Signed Certificate": "Selbstsigniertes Zertifikat erneuern",
    "Delete current certificate. A new one will be generated on next start.": "Aktuelles Zertifikat löschen. Ein neues wird beim nächsten Start generiert.",
    "Delete Certificate": "Zertifikat löschen",
    "Remove the self-signed certificate and private key": "Selbstsigniertes Zertifikat und privaten Schlüssel entfernen",
    "Network (0.0.0.0 + TLS)": "Netzwerk (0.0.0.0 + TLS)",
    "Search Directory": "Verzeichnis durchsuchen",
    "All Accounts": "Alle Konten",
    "Search directory for '%s'": "Verzeichnis nach '%s' durchsuchen",
    "Backup Restored": "Backup wiederhergestellt",
    "Wrong password.\n\nPlease enter the password that was active for the database when the backup was created.": "Falsches Passwort.\n\nBitte geben Sie das Passwort ein, das beim Erstellen des Backups für die Datenbank aktiv war.",
    "A backup has been restored.\n\nPlease enter the password that was active for the database when the backup was created.": "Ein Backup wurde wiederhergestellt.\n\nBitte geben Sie das Passwort ein, das beim Erstellen des Backups für die Datenbank aktiv war.",
    "On first use, you need to set a password. Without a password, DinoX cannot open the encrypted database.": "Bei der ersten Verwendung müssen Sie ein Passwort festlegen. Ohne Passwort kann DinoX die verschlüsselte Datenbank nicht öffnen.",
    "This password is used to encrypt your local DinoX data.": "Dieses Passwort wird verwendet, um Ihre lokalen DinoX-Daten zu verschlüsseln.",
    "Decrypting Backup…": "Backup wird entschlüsselt…",
    "Restoring Backup…": "Backup wird wiederhergestellt…",
    "Please wait, this may take a moment…": "Bitte warten, dies kann einen Moment dauern…",
    "Creating Backup…": "Backup wird erstellt…",
    "Creating Encrypted Backup…": "Verschlüsseltes Backup wird erstellt…",
    "Decrypting encrypted backup file…": "Verschlüsselte Backup-Datei wird entschlüsselt…",
    "Extracting files from backup…": "Dateien werden aus dem Backup extrahiert…",
    "Valid": "Gültig",
    "Valid (CA-signed)": "Gültig (CA-signiert)",
    "Valid:": "Gültig:",
    "Invalid / expired": "Ungültig / abgelaufen",
    "Not found / expired": "Nicht gefunden / abgelaufen",
    "expired": "abgelaufen",
    "Pinned (self-signed / manually trusted)": "Angeheftet (selbstsigniert / manuell vertraut)",
    "Pinned (not connected)": "Angeheftet (nicht verbunden)",
    "SHA-256 Fingerprint:": "SHA-256-Fingerabdruck:",
    "Issuer:": "Aussteller:",
    "Until:": "Bis:",
    "Protocol: %s": "Protokoll: %s",
    "Remove pinned certificate for %s?": "Angeheftetes Zertifikat für %s entfernen?",
    "The server will need to present a valid CA-signed certificate, or you will be asked to trust it again.": "Der Server muss ein gültiges CA-signiertes Zertifikat vorweisen, oder Sie werden erneut aufgefordert, ihm zu vertrauen.",
    "Proxy unreachable": "Proxy nicht erreichbar",
    "Also delete account from server": "Konto auch vom Server löschen",
    "Also delete for chat partner": "Auch für Chatpartner löschen",
    "Leave Conversation": "Unterhaltung verlassen",
    "You won't be able to access your conversation history anymore.": "Sie können danach nicht mehr auf Ihren Unterhaltungsverlauf zugreifen.",
    "File could not be downloaded": "Datei konnte nicht heruntergeladen werden",
    "Uploading…": "Wird hochgeladen…",
    "Video recording failed": "Videoaufnahme fehlgeschlagen",
    "The video encoder could not be initialized: %s\n\nPlease ensure GStreamer plugins are installed (gst-plugins-good, gst-plugins-ugly, gst-libav).": "Der Video-Encoder konnte nicht initialisiert werden: %s\n\nBitte stellen Sie sicher, dass GStreamer-Plugins installiert sind (gst-plugins-good, gst-plugins-ugly, gst-libav).",
    "WebRTC Gain:": "WebRTC-Verstärkung:",
    "Unknown Status": "Unbekannter Status",
    "DinoX will now restart…": "DinoX wird jetzt neu gestartet…",
    "Resetting database… DinoX will restart.": "Datenbank wird zurückgesetzt… DinoX wird neu gestartet.",
    "Factory reset in progress… DinoX will restart.": "Werksreset wird durchgeführt… DinoX wird neu gestartet.",
    "This will delete cached files, avatars, previews and database caches (entity discovery, roster, MAM sync state, stickers).\n\nAll data will be re-fetched from the server when needed.": "Dies löscht zwischengespeicherte Dateien, Avatare, Vorschauen und Datenbank-Caches (Entity-Discovery, Kontaktliste, MAM-Sync-Status, Sticker).\n\nAlle Daten werden bei Bedarf erneut vom Server abgerufen.",
    "Cache cleared (%s freed, %d DB rows removed)": "Cache geleert (%s freigegeben, %d Datenbankzeilen entfernt)",
    "Local chat history cleared.": "Lokaler Chatverlauf gelöscht.",
    "Done! Chat history has been cleaned up.": "Fertig! Der Chatverlauf wurde bereinigt.",
    "Error clearing local history: %s": "Fehler beim Löschen des lokalen Verlaufs: %s",
    "Chat history cleared.": "Chatverlauf gelöscht.",
    "No local conversation found for %s.": "Keine lokale Unterhaltung für %s gefunden.",
    "WARNING: ejabberd does NOT support per-user MAM deletion.": "WARNUNG: ejabberd unterstützt NICHT die MAM-Löschung pro Benutzer.",
    "This will delete the ENTIRE server message archive for ALL users on this domain!": "Dies löscht das GESAMTE Server-Nachrichtenarchiv für ALLE Benutzer dieser Domain!",
    "Deleting server message archive (ALL users)...": "Server-Nachrichtenarchiv wird gelöscht (ALLE Benutzer)...",
    "Server message archive (MAM) cleared.": "Server-Nachrichtenarchiv (MAM) gelöscht.",
    "MAM delete failed: %s": "MAM-Löschung fehlgeschlagen: %s",
    "ejabberd API not configured.": "ejabberd-API nicht konfiguriert.",
    "present and valid": "vorhanden und gültig",
    "will be generated on start": "wird beim Start generiert",
    "Files, reactions, rooms": "Dateien, Reaktionen, Räume",
    "Messages in both directions": "Nachrichten in beide Richtungen",
    "Messages in both directions (default)": "Nachrichten in beide Richtungen (Standard)",
    "Filter by account:": "Nach Konto filtern:",
    "Send as account": "Senden als Konto",

    # Bot features
    "Bot #%d not found or does not belong to you.": "Bot #%d nicht gefunden oder gehört nicht Ihnen.",
    "Unknown command. Type /help for a list of available commands.": "Unbekannter Befehl. Geben Sie /help für eine Liste verfügbarer Befehle ein.",
    "Create a new bot": "Neuen Bot erstellen",
    "Send the name for your bot:": "Senden Sie den Namen für Ihren Bot:",
    "You already have 20 bots. Delete one first with /deletebot.": "Sie haben bereits 20 Bots. Löschen Sie zuerst einen mit /deletebot.",
    "Bot created!": "Bot erstellt!",
    "Name: %s": "Name: %s",
    "List your bots": "Ihre Bots auflisten",
    "Delete a bot": "Bot löschen",
    "Activate a bot": "Bot aktivieren",
    "Deactivate a bot": "Bot deaktivieren",
    "Bot details": "Bot-Details",
    "Set bot commands": "Bot-Befehle setzen",
    "Set description": "Beschreibung setzen",
    "Test bot": "Bot testen",
    "Set up webhook": "Webhook einrichten",
    "Show/change mode": "Modus anzeigen/ändern",
    "Show/change model": "Modell anzeigen/ändern",
    "Show/change system prompt": "System-Prompt anzeigen/ändern",
    "Clear chat history": "Chatverlauf leeren",
    "Show status": "Status anzeigen",
    "Show all providers": "Alle Anbieter anzeigen",
    "Switch provider": "Anbieter wechseln",
    "Set up AI": "KI einrichten",
    "Turn on AI": "KI aktivieren",
    "Turn off AI": "KI deaktivieren",
    "Show current token": "Aktuellen Token anzeigen",
    "Regenerate token": "Token neu generieren",
    "Revoke token": "Token widerrufen",
    "Set up Telegram": "Telegram einrichten",
    "Turn on Telegram": "Telegram aktivieren",
    "Turn off bridge": "Brücke deaktivieren",
    "Turn on bridge": "Brücke aktivieren",
    "Activate Bot": "Bot aktivieren",
    "Deactivate Bot": "Bot deaktivieren",
    "Your Bots": "Ihre Bots",
    "You don't have any bots yet.": "Sie haben noch keine Bots.",
    "Total: %d bot(s)": "Gesamt: %d Bot(s)",
    "Bots: %d total, %d active": "Bots: %d gesamt, %d aktiv",
    "Bot: %s": "Bot: %s",
    "Send: /newbot": "Senden: /newbot",
    "See your bots:": "Ihre Bots ansehen:",
    "Create your first bot:": "Erstellen Sie Ihren ersten Bot:",
    "Welcome! I am %s.": "Willkommen! Ich bin %s.",
    "Bot '%s' (ID: %d) activated.": "Bot '%s' (ID: %d) aktiviert.",
    "Bot '%s' (ID: %d) deactivated.": "Bot '%s' (ID: %d) deaktiviert.",
    "Bot '%s' (ID: %d) deleted.": "Bot '%s' (ID: %d) gelöscht.",
    "Bot '%s' (ID: %d) is already active.": "Bot '%s' (ID: %d) ist bereits aktiv.",
    "Bot '%s' (ID: %d) is already inactive.": "Bot '%s' (ID: %d) ist bereits inaktiv.",
    "Bot '%s' deleted, but ejabberd account '%s' could not be removed: %s\nManual cleanup may be needed.": "Bot '%s' gelöscht, aber ejabberd-Konto '%s' konnte nicht entfernt werden: %s\nManuelle Bereinigung könnte erforderlich sein.",
    "Bot Management": "Bot-Verwaltung",
    "Bot is now disabled.": "Bot ist jetzt deaktiviert.",
    "The bot is now offline. API requests will be rejected.": "Der Bot ist jetzt offline. API-Anfragen werden abgelehnt.",
    "The bot is now online and accepts API requests.": "Der Bot ist jetzt online und akzeptiert API-Anfragen.",
    "active": "aktiv",
    "No valid commands found.": "Keine gültigen Befehle gefunden.",
    "Format: /cmd - description": "Format: /cmd - Beschreibung",
    "Custom commands:": "Eigene Befehle:",
    "%d command(s) set for '%s'.": "%d Befehl(e) für '%s' gesetzt.",
    "Description for '%s' updated.": "Beschreibung für '%s' aktualisiert.",
    "Account '%s' not found.": "Konto '%s' nicht gefunden.",

    # Token management
    "Token": "Token",
    "Show Token": "Token anzeigen",
    "Regenerate Token": "Token neu generieren",
    "Revoke Token": "Token widerrufen",
    "Token for '%s' (ID: %d)": "Token für '%s' (ID: %d)",
    "New Token for '%s'": "Neuer Token für '%s'",
    "Token revoked for '%s' (ID: %d)": "Token widerrufen für '%s' (ID: %d)",
    "Token is now invalid.": "Token ist jetzt ungültig.",
    "The old token is now invalid.": "Der alte Token ist jetzt ungültig.",
    "Save this token! It won't be shown again.": "Speichern Sie diesen Token! Er wird nicht erneut angezeigt.",
    "Tokens are shown only once at creation and not stored.": "Token werden nur einmal bei der Erstellung angezeigt und nicht gespeichert.",
    "Tokens are shown only once at creation.": "Token werden nur einmal bei der Erstellung angezeigt.",
    "Token management:": "Token-Verwaltung:",
    "Regenerate token:": "Token neu generieren:",
    "Revoke token:": "Token widerrufen:",
    "Regenerate: /token %d": "Neu generieren: /token %d",

    # AI features
    "AI Assistant": "KI-Assistent",
    "AI Providers": "KI-Anbieter",
    "AI Setup": "KI-Einrichtung",
    "AI Setup: %s": "KI-Einrichtung: %s",
    "AI activated!": "KI aktiviert!",
    "AI assistant setup & control": "KI-Assistenten-Einrichtung & Steuerung",
    "AI conversation history cleared.": "KI-Unterhaltungsverlauf gelöscht.",
    "AI deactivated.": "KI deaktiviert.",
    "AI is already active.": "KI ist bereits aktiv.",
    "AI not configured.": "KI nicht konfiguriert.",
    "AI: %s": "KI: %s",
    "AI: %s (%s / %s)": "KI: %s (%s / %s)",
    "AI: not configured": "KI: nicht konfiguriert",
    "Activate AI": "KI aktivieren",
    "Set up AI now": "KI jetzt einrichten",
    "Choose a provider:": "Wählen Sie einen Anbieter:",
    "All providers with models:": "Alle Anbieter mit Modellen:",
    "All providers with models: /ki providers": "Alle Anbieter mit Modellen: /ki providers",
    "All providers:": "Alle Anbieter:",
    "All providers: /ki setup": "Alle Anbieter: /ki setup",
    "Available models for %s:": "Verfügbare Modelle für %s:",
    "Provider: %s": "Anbieter: %s",
    "Current mode: %s": "Aktueller Modus: %s",
    "Current model: %s": "Aktuelles Modell: %s",
    "Current system prompt:": "Aktueller System-Prompt:",
    "Model: %s": "Modell: %s",
    "Mode: %s": "Modus: %s",
    "Models:": "Modelle:",
    "Modes: personal, dedicated, cloud": "Modi: personal, dedicated, cloud",
    "Mode changed: %s": "Modus geändert: %s",
    "Model changed: %s": "Modell geändert: %s",
    "System prompt updated:": "System-Prompt aktualisiert:",
    "Change mode:": "Modus ändern:",
    "Change model:": "Modell ändern:",
    "Change with:": "Ändern mit:",
    "Set system prompt": "System-Prompt setzen",
    "Just send a message for the AI!": "Senden Sie einfach eine Nachricht für die KI!",
    "Unknown provider: %s": "Unbekannter Anbieter: %s",
    "(No token needed - localhost only)": "(Kein Token erforderlich - nur localhost)",
    "(Not yet configured)": "(Noch nicht konfiguriert)",
    "(Depends on your Ollama installation)": "(Abhängig von Ihrer Ollama-Installation)",
    "(unknown provider)": "(unbekannter Anbieter)",
    "Available: openai, claude, gemini, groq, mistral, deepseek, perplexity, ollama, openclaw": "Verfügbar: openai, claude, gemini, groq, mistral, deepseek, perplexity, ollama, openclaw",
    "No API key needed (local, use - as placeholder)": "Kein API-Schlüssel erforderlich (lokal, verwenden Sie - als Platzhalter)",
    "Unknown: /ki %s": "Unbekannt: /ki %s",
    "Authentication & token": "Authentifizierung & Token",
    "OpenClaw is an autonomous AI agent/orchestrator.": "OpenClaw ist ein autonomer KI-Agent/Orchestrator.",
    "Autonomous AI agent": "Autonomer KI-Agent",
    "It manages multiple AI models independently.": "Er verwaltet mehrere KI-Modelle unabhängig.",
    "Token: from your OpenClaw Gateway config": "Token: aus Ihrer OpenClaw-Gateway-Konfiguration",
    "(OpenClaw manages models internally)": "(OpenClaw verwaltet Modelle intern)",

    # Telegram Bridge
    "Telegram Bridge": "Telegram-Brücke",
    "Telegram Setup": "Telegram-Einrichtung",
    "Telegram bridge activated!": "Telegram-Brücke aktiviert!",
    "Telegram bridge configured and started!": "Telegram-Brücke konfiguriert und gestartet!",
    "Telegram bridge deactivated.": "Telegram-Brücke deaktiviert.",
    "Telegram bridge is already active.": "Telegram-Brücke ist bereits aktiv.",
    "Telegram bridge setup & control": "Telegram-Brücken-Einrichtung & Steuerung",
    "Telegram not configured.": "Telegram nicht konfiguriert.",
    "Telegram: %s": "Telegram: %s",
    "Telegram: not configured": "Telegram: nicht konfiguriert",
    "Set up Telegram now": "Telegram jetzt einrichten",
    "Only XMPP -> Telegram": "Nur XMPP -> Telegram",
    "Unknown: /telegram %s": "Unbekannt: /telegram %s",
    "Step 1: Get a bot token": "Schritt 1: Bot-Token besorgen",
    "Open Telegram and message @BotFather": "Öffnen Sie Telegram und schreiben Sie @BotFather",
    "You will receive a token (e.g. 123456:ABC-DEF1234)": "Sie erhalten einen Token (z. B. 123456:ABC-DEF1234)",
    "Step 2: Find your chat ID": "Schritt 2: Chat-ID ermitteln",
    "Message @userinfobot on Telegram": "Schreiben Sie @userinfobot auf Telegram",
    "It will reply with your chat ID (e.g. 987654321)": "Er antwortet mit Ihrer Chat-ID (z. B. 987654321)",
    "Step 3: Configure here": "Schritt 3: Hier konfigurieren",
    "Chat ID: %s": "Chat-ID: %s",

    # API docs
    "API: Advanced Features": "API: Erweiterte Funktionen",
    "API: Authentication": "API: Authentifizierung",
    "API: Bot Management": "API: Bot-Verwaltung",
    "API: Messages": "API: Nachrichten",
    "API: Quick Start": "API: Schnellstart",
    "API: Server Settings": "API: Servereinstellungen",
    "API: Server Status": "API: Serverstatus",
    "API: http://localhost:7842": "API: http://localhost:7842",
    "API port set to %d.": "API-Port auf %d gesetzt.",
    "API server mode set to 'local'.": "API-Servermodus auf 'local' gesetzt.",
    "API server mode set to 'network'.": "API-Servermodus auf 'network' gesetzt.",
    "API server settings": "API-Servereinstellungen",
    "Quick start with curl": "Schnellstart mit curl",
    "Quick start:": "Schnellstart:",
    "All endpoints:": "Alle Endpunkte:",
    "All bot endpoints require a Bearer token.": "Alle Bot-Endpunkte erfordern einen Bearer-Token.",
    "Header: Authorization: Bearer <TOKEN>": "Header: Authorization: Bearer <TOKEN>",
    "Replace <TOKEN> with your bot token (/showtoken <ID>)": "Ersetzen Sie <TOKEN> durch Ihren Bot-Token (/showtoken <ID>)",
    "All responses: {\"ok\": true/false, \"result\": ...}": "Alle Antworten: {\"ok\": true/false, \"result\": ...}",
    "Send & receive messages": "Nachrichten senden & empfangen",
    "Send message (POST → JSON):": "Nachricht senden (POST → JSON):",
    "Recipient JID (required)": "Empfänger-JID (erforderlich)",
    "Message text (required)": "Nachrichtentext (erforderlich)",
    "Get messages": "Nachrichten abrufen",
    "Max count, 1-100 (default: 100)": "Maximale Anzahl, 1-100 (Standard: 100)",
    "Updates from this ID (optional)": "Aktualisierungen ab dieser ID (optional)",
    "With offset (acknowledge previous):": "Mit Offset (vorherige bestätigen):",
    "Response format:": "Antwortformat:",
    "Get bot info (GET → JSON):": "Bot-Info abrufen (GET → JSON):",
    "Set Bot Commands": "Bot-Befehle setzen",
    "Set Bot Description": "Bot-Beschreibung setzen",
    "Parameters:": "Parameter:",
    "Get commands: GET /bot/getCommands": "Befehle abrufen: GET /bot/getCommands",
    "Files, reactions, rooms": "Dateien, Reaktionen, Räume",
    "Response:": "Antwort:",
    "Response contains a secret for signature verification.": "Die Antwort enthält ein Geheimnis zur Signaturprüfung.",
    "DinoX sends POST to your URL with:": "DinoX sendet POST an Ihre URL mit:",
    "Verify signature (Python):": "Signatur prüfen (Python):",
    "POST body field: \"text\" (not \"body\")": "POST-Body-Feld: \"text\" (nicht \"body\")",
    "Note for curl:": "Hinweis für curl:",
    "Management endpoints (no token needed):": "Verwaltungsendpunkte (kein Token erforderlich):",
    "Base URL: %s://localhost:%d": "Basis-URL: %s://localhost:%d",
    "Python example:": "Python-Beispiel:",
    "Leave: POST /bot/leaveRoom": "Verlassen: POST /bot/leaveRoom",
    "Next steps:": "Nächste Schritte:",
    "Details & Setup:": "Details & Einrichtung:",
    "Details for a provider:": "Details zu einem Anbieter:",
    "Next:": "Weiter:",
    "Next: /api webhook": "Weiter: /api webhook",
    "Back:": "Zurück:",
    "Back: /api": "Zurück: /api",
    "Back: /api server": "Zurück: /api server",
    "Back: /help": "Zurück: /help",
    "Back: /ki": "Zurück: /ki",
    "Back: /telegram": "Zurück: /telegram",
    "Menus:": "Menüs:",
    "Examples:": "Beispiele:",
    "Example:": "Beispiel:",
    "Notes:": "Hinweise:",
    "Basic commands:": "Grundbefehle:",
    "Create, delete, manage bots": "Bots erstellen, löschen, verwalten",
    "HTTP API & webhook documentation": "HTTP-API- & Webhook-Dokumentation",
    "Reactivate:": "Reaktivieren:",
    "Current:": "Aktuell:",
    "Available: bridge, forward": "Verfügbar: bridge, forward",
    "Change port (1024-65535)": "Port ändern (1024-65535)",
    "Local (127.0.0.1)": "Lokal (127.0.0.1)",
    "Local (HTTP)": "Lokal (HTTP)",
    "Local (localhost)": "Lokal (localhost)",
    "Localhost only (no TLS)": "Nur localhost (kein TLS)",
    "Network (HTTPS)": "Netzwerk (HTTPS)",
    "All interfaces (with TLS)": "Alle Schnittstellen (mit TLS)",
    "For external access: nginx reverse proxy": "Für externen Zugriff: nginx Reverse-Proxy",
    "No TLS (localhost-only is secure).": "Kein TLS (nur-localhost ist sicher).",
    "The server listens on all interfaces (0.0.0.0) with TLS.": "Der Server lauscht auf allen Schnittstellen (0.0.0.0) mit TLS.",
    "The server listens only on localhost (127.0.0.1).": "Der Server lauscht nur auf localhost (127.0.0.1).",
    "Don't forget to also set the key:": "Vergessen Sie nicht, auch den Schlüssel zu setzen:",
    "or activate network mode.": "oder aktivieren Sie den Netzwerkmodus.",
    "or": "oder",
    "etc.": "usw.",
    "(auto-detect)": "(automatisch erkennen)",
    "(default)": "(Standard)",
    "(not set)": "(nicht gesetzt)",
    "(only accessible from localhost)": "(nur von localhost erreichbar)",
    "(personal)": "(persönlich)",
    "(request pending)": "(Anfrage ausstehend)",
    "(without key shows help)": "(ohne Schlüssel zeigt Hilfe)",
    "(incl. commands & sessions)": "(inkl. Befehle & Sitzungen)",
    "off": "aus",
    "local": "lokal",

    # TLS / Certificate
    "TLS Certificate:": "TLS-Zertifikat:",
    "TLS Configuration:": "TLS-Konfiguration:",
    "Automatic (self-signed)": "Automatisch (selbstsigniert)",
    "Mode: Automatic (self-signed)": "Modus: Automatisch (selbstsigniert)",
    "Mode: Custom certificate": "Modus: Eigenes Zertifikat",
    "Custom cert:": "Eigenes Zertifikat:",
    "Custom certificate (PEM)": "Eigenes Zertifikat (PEM)",
    "Custom key (PEM)": "Eigener Schlüssel (PEM)",
    "Self-signed:": "Selbstsigniert:",
    "Back to self-signed": "Zurück zu selbstsigniert",
    "Generate new cert": "Neues Zertifikat generieren",
    "Delete cert": "Zertifikat löschen",
    "A self-signed certificate will be generated automatically.": "Ein selbstsigniertes Zertifikat wird automatisch generiert.",
    "A new one will be generated on next start in network mode.": "Ein neues wird beim nächsten Start im Netzwerkmodus generiert.",
    "Empty = auto-generated self-signed": "Leer = automatisch generiertes selbstsigniertes",
    "Certificate and key deleted.": "Zertifikat und Schlüssel gelöscht.",
    "Certificate deleted. Server will restart with new certificate.": "Zertifikat gelöscht. Server wird mit neuem Zertifikat neu gestartet.",
    "Certificate: %s": "Zertifikat: %s",
    "Key: %s": "Schlüssel: %s",
    "TLS certificate path set: %s": "TLS-Zertifikatspfad gesetzt: %s",
    "TLS key path set: %s": "TLS-Schlüsselpfad gesetzt: %s",
    "TLS certificate set to automatic (self-signed).": "TLS-Zertifikat auf automatisch (selbstsigniert) gesetzt.",
    "Self-signed certificate deleted.": "Selbstsigniertes Zertifikat gelöscht.",
    "New self-signed certificate created!": "Neues selbstsigniertes Zertifikat erstellt!",
    "Server will restart automatically with the new certificate.": "Server wird automatisch mit dem neuem Zertifikat neu gestartet.",
    "Error creating certificate (code: %d).": "Fehler beim Erstellen des Zertifikats (Code: %d).",
    "Path: %s": "Pfad: %s",
    "Port: %d": "Port: %d",
    "Service is running and reachable": "Dienst ist gestartet und erreichbar",
    "Detailed status": "Detaillierter Status",
    "Test connection": "Verbindung testen",
    "Your API Token:": "Ihr API-Token:",
    "Generate a new token:": "Neuen Token generieren:",

    # Misc
    "Prosody (mod_pubsub_mqtt) — read-only": "Prosody (mod_pubsub_mqtt) — schreibgeschützt",
    "Unknown / Not detected": "Unbekannt / Nicht erkannt",
    "MQTT connection for %s": "MQTT-Verbindung für %s",
    "MQTT Bot": "MQTT-Bot",
    "Enable MQTT in Preferences > Account > MQTT Bot.": "MQTT aktivieren unter Einstellungen > Konto > MQTT-Bot.",
    "Note: Changes are applied automatically.": "Hinweis: Änderungen werden automatisch angewendet.",
    "Changes applied automatically.": "Änderungen automatisch angewendet.",
    "Disconnected (retrying…)": "Getrennt (Wiederversuch…)",
    "No active MQTT connections.\n": "Keine aktiven MQTT-Verbindungen.\n",

    # Webhook
    "1. Create bot": "1. Bot erstellen",
    "1. Send file": "1. Datei senden",
    "1. Send message": "1. Nachricht senden",
    "1. Set up webhook": "1. Webhook einrichten",
    "2. List bots": "2. Bots auflisten",
    "2. Receive messages (polling)": "2. Nachrichten empfangen (Polling)",
    "2. Remove webhook": "2. Webhook entfernen",
    "2. Send reaction": "2. Reaktion senden",
    "3. Delete bot": "3. Bot löschen",
    "3. Join group room": "3. Gruppenraum beitreten",
    "3. Webhook format": "3. Webhook-Format",
    "4. Activate/deactivate bot": "4. Bot aktivieren/deaktivieren",
    "4. Register bot commands": "4. Bot-Befehle registrieren",
    "5. Bot information": "5. Bot-Informationen",
    "From:": "Von:",
    "Optional with mode:": "Optional mit Modus:",
    "Usage:": "Verwendung:",

    # Server info hints
    "\u0131nfo Server: ejabberd (mod_mqtt detected)\n\nejabberd shares XMPP and MQTT authentication.\nYou can use your XMPP credentials to connect\nto the MQTT broker on the same domain.\n\nPer-account mode uses these credentials automatically.": "\u0131nfo Server: ejabberd (mod_mqtt erkannt)\n\nejabberd teilt XMPP- und MQTT-Authentifizierung.\nSie können Ihre XMPP-Anmeldedaten verwenden,\num sich mit dem MQTT-Broker auf derselben Domain zu verbinden.\n\nDer Pro-Konto-Modus verwendet diese Anmeldedaten automatisch.",
    "💡 Your XMPP server (%s) supports MQTT!\n\n": "💡 Ihr XMPP-Server (%s) unterstützt MQTT!\n\n",
    "\u26a0 Server: Prosody (mod_pubsub_mqtt detected)\n\nProsody's MQTT bridge does NOT support authentication.\nAny client on the network can subscribe to topics.\n\nRecommendations:\n\u2022 Restrict MQTT port via firewall\n\u2022 Use TLS for encryption\n\u2022 Do not publish sensitive data\n\nTopic format: <HOST>/<TYPE>/<NODE>": "\u26a0 Server: Prosody (mod_pubsub_mqtt erkannt)\n\nProsodys MQTT-Brücke unterstützt KEINE Authentifizierung.\nJeder Client im Netzwerk kann Themen abonnieren.\n\nEmpfehlungen:\n\u2022 MQTT-Port per Firewall einschränken\n\u2022 TLS zur Verschlüsselung verwenden\n\u2022 Keine sensiblen Daten veröffentlichen\n\nThemenformat: <HOST>/<TYPE>/<NODE>",

    # The gigantic help string - keep it as-is (commands should stay English)
    # We skip this one intentionally - too complex and mostly commands
}


def apply_translations(lang_code, translations, dry_run=True):
    """Apply translations to a PO file."""
    po_path = PO_DIR / f"{lang_code}.po"
    if not po_path.exists():
        print(f"  PO file not found: {po_path}")
        return 0, 0

    # Backup
    if not dry_run:
        backup = po_path.with_suffix('.po.bak')
        shutil.copy2(po_path, backup)

    po = polib.pofile(str(po_path))
    applied = 0
    errors = 0

    for entry in po.untranslated_entries():
        if entry.msgid in translations:
            msgstr = translations[entry.msgid]

            # Validate
            ok, errs = validate_translation(entry.msgid, msgstr)
            if not ok:
                print(f"  ✘ VALIDATION FAILED: {repr(entry.msgid[:50])}")
                for e in errs:
                    print(f"    → {e}")
                errors += 1
                continue

            if not dry_run:
                entry.msgstr = msgstr
            applied += 1

    # Also fix fuzzy entries  
    for entry in po.fuzzy_entries():
        if entry.msgid in translations:
            msgstr = translations[entry.msgid]
            ok, errs = validate_translation(entry.msgid, msgstr)
            if ok:
                if not dry_run:
                    entry.msgstr = msgstr
                    if 'fuzzy' in entry.flags:
                        entry.flags.remove('fuzzy')
                applied += 1

    if not dry_run and applied > 0:
        po.save(str(po_path))

    return applied, errors


def run_msgfmt_check(lang_code):
    """Run msgfmt --check on a PO file."""
    po_path = PO_DIR / f"{lang_code}.po"
    result = subprocess.run(
        ['msgfmt', '--check-format', '--check-header', '-o', '/dev/null', str(po_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  ✘ msgfmt check FAILED for {lang_code}:")
        print(f"    {result.stderr.strip()}")
        return False
    print(f"  ✔ msgfmt check passed for {lang_code}")
    return True


def run_pofilter_check(lang_code):
    """Run pofilter on a PO file for comprehensive QA."""
    po_path = PO_DIR / f"{lang_code}.po"
    try:
        result = subprocess.run(
            ['pofilter', '--excludefilter=untranslated',
             '--excludefilter=isfuzzy',
             str(po_path)],
            capture_output=True, text=True, timeout=30
        )
        # Count issues
        issues = result.stdout.count('msgid "')
        if issues > 0:
            print(f"  ⚠ pofilter found {issues} potential issues for {lang_code}")
            # Show first few
            lines = result.stdout.split('\n')
            shown = 0
            for i, line in enumerate(lines):
                if line.startswith('#') or line.startswith('msgid') or line.startswith('msgstr'):
                    print(f"    {line}")
                    shown += 1
                    if shown > 15:
                        print(f"    ... ({issues} total issues)")
                        break
        else:
            print(f"  ✔ pofilter clean for {lang_code}")
        return issues == 0
    except FileNotFoundError:
        print(f"  ⚠ pofilter not found, skipping")
        return True
    except subprocess.TimeoutExpired:
        print(f"  ⚠ pofilter timeout for {lang_code}")
        return True


def main():
    dry_run = '--apply' not in sys.argv
    check_only = '--check' in sys.argv

    if check_only:
        print("=== Validation Only ===\n")
        for lang in ['de', 'fr', 'es']:
            print(f"\n--- {lang} ---")
            run_msgfmt_check(lang)
            run_pofilter_check(lang)
        return

    mode = "DRY RUN" if dry_run else "APPLYING"
    print(f"=== Translation Script ({mode}) ===\n")

    langs = {
        'de': DE,
        'fr': FR,
        'es': ES,
    }

    for lang_code, trans_dict in langs.items():
        print(f"\n--- {lang_code.upper()} ({len(trans_dict)} translations) ---")

        # Pre-validate all translations
        pre_errors = 0
        for msgid, msgstr in trans_dict.items():
            ok, errs = validate_translation(msgid, msgstr)
            if not ok:
                print(f"  ✘ PRE-CHECK FAILED: {repr(msgid[:50])}")
                for e in errs:
                    print(f"    → {e}")
                pre_errors += 1

        if pre_errors > 0:
            print(f"\n  ⚠ {pre_errors} translations failed pre-check!")
            if not dry_run:
                print(f"  Skipping {lang_code} due to errors.")
                continue

        applied, errors = apply_translations(lang_code, trans_dict, dry_run)
        print(f"\n  Applied: {applied}, Errors: {errors}")

        if not dry_run and applied > 0:
            print(f"\n  Post-validation:")
            run_msgfmt_check(lang_code)
            run_pofilter_check(lang_code)

    if dry_run:
        print("\n\n=== This was a DRY RUN. Use --apply to write changes. ===")


if __name__ == '__main__':
    main()
