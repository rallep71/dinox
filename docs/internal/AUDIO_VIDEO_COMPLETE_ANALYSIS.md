# DinoX Audio/Video - Komplette Architektur-Analyse

**Datum:** 12. Dezember 2025  
**Version:** 1.1  
**Zweck:** Vollständige Dokumentation der Audio/Video-Architektur für DinoX mit Vergleich zum Original Dino

---

## 📋 INHALTSVERZEICHNIS

1. [Übersicht](#1-übersicht)
2. [Dateistruktur](#2-dateistruktur)
3. [Datenfluss-Diagramme](#3-datenfluss-diagramme)
4. [Detaillierte Dateianalyse](#4-detaillierte-dateianalyse)
5. [Dino vs DinoX Vergleich](#5-dino-vs-dinox-vergleich)
6. [Signalisierung (Jingle)](#6-signalisierung-jingle)
7. [ICE/DTLS Negotiation](#7-icedtls-negotiation)
8. [Race Conditions & Timing](#8-race-conditions--timing)
9. [Bekannte Probleme & Ursachen](#9-bekannte-probleme--ursachen)
10. [Debug-Anleitung](#10-debug-anleitung)
11. [Empfehlungen](#11-empfehlungen)
12. [libnice 0.1.23 Analyse](#12-libnice-0123-analyse)
13. [Fazit](#13-fazit)

---

# 1. ÜBERSICHT

## 1.1 Was ist DinoX?

DinoX ist ein Fork des XMPP-Clients Dino mit Fokus auf verbesserte Audio/Video-Anrufe. Die Implementierung basiert auf:

| Komponente | Technologie | Zweck |
|------------|-------------|-------|
| **GStreamer** | Multimedia Framework | Audio/Video Pipeline |
| **libnice** | ICE Library (v0.1.23) | NAT Traversal |
| **GnuTLS** | TLS Library | DTLS-SRTP Verschlüsselung |
| **Jingle** | XMPP Extension | Signalisierung |

> **📌 WICHTIG:** libnice 0.1.23 wurde am 6. Dezember 2025 von der Source kompiliert!  
> Installiert in: `/usr/lib/x86_64-linux-gnu/libnice.so.10.15.0`

## 1.2 Unterstützte Codecs

| Typ | Codec | Payload Type | Encoder |
|-----|-------|--------------|---------|
| Audio | Opus | 111 | opusenc |
| Video | VP8 | 96/97 | vp8enc, vavp8enc |
| Video | VP9 | 98 | vp9enc, vavp9enc |
| Video | H.264 | 102 | x264enc, vaapih264enc |

---

# 2. DATEISTRUKTUR

## 2.1 Wichtige Dateien

```
plugins/
├── rtp/src/
│   ├── stream.vala          # 946 Zeilen - Haupt-RTP-Stream
│   ├── plugin.vala           # 599 Zeilen - Plugin-Verwaltung
│   ├── device.vala           # 626 Zeilen - Geräte-Management
│   ├── codec_util.vala       # 453 Zeilen - Codec-Konfiguration
│   ├── voice_processor.vala  # 210 Zeilen - Echo-Unterdrückung
│   ├── video_widget.vala     # ~350 Zeilen - Video-Anzeige
│   └── module.vala           # ~250 Zeilen - Jingle RTP Modul
│
├── ice/src/
│   ├── transport_parameters.vala  # 539 Zeilen - ICE/DTLS Transport
│   ├── dtls_srtp.vala             # 488 Zeilen - DTLS/SRTP Verschlüsselung
│   ├── module.vala                # ~100 Zeilen - ICE Modul
│   └── util.vala                  # ~50 Zeilen - Hilfsfunktionen
```

## 2.2 Dateigrößen-Vergleich

| Datei | Original Dino | DinoX | Änderung |
|-------|---------------|-------|----------|
| stream.vala | ~850 Zeilen | 946 Zeilen | **+11%** |
| transport_parameters.vala | ~389 Zeilen | 539 Zeilen | **+39%** |
| dtls_srtp.vala | ~280 Zeilen | 488 Zeilen | **+74%** |

---

# 3. DATENFLUSS-DIAGRAMME

## 3.1 Ausgehender Medienfluss (Senden)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    AUSGEHENDER AUDIO/VIDEO FLUSS                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐                                                         │
│  │ Mikrofon/   │                                                         │
│  │ Kamera      │                                                         │
│  └──────┬──────┘                                                         │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ device.vala     │  Device.link_source()                               │
│  │ - capsfilter    │  - Erstellt GStreamer Element                       │
│  │ - VoiceProcessor│  - Verbindet Echo-Unterdrückung (Audio)             │
│  │ - tee           │  - Erlaubt mehrere Ausgänge                         │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ codec_util.vala │  get_encode_bin()                                   │
│  │ - videoconvert  │  - Erstellt Encoder-Pipeline                        │
│  │ - vp8enc/opus   │  - Konfiguriert Codec-Parameter                     │
│  │ - rtpvp8pay     │  - Fügt RTP-Payloader hinzu                         │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ stream.vala     │  create()                                           │
│  │ - rtpbin        │  - Verbindet mit RTP-Bin                            │
│  │ - send_rtp      │  - appsink für RTP-Pakete                           │
│  │ - send_rtcp     │  - appsink für RTCP-Pakete                          │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐  on_new_sample()                                    │
│  │ stream.vala     │  - Holt Buffer aus appsink                          │
│  │ encrypt_rtp()   │  - Verschlüsselt mit SRTP                           │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌──────────────────────┐                                                │
│  │ transport_params.vala│  DatagramConnection.send_datagram()            │
│  │ - DTLS-Pufferung     │  - Puffert wenn DTLS nicht bereit              │
│  │ - SRTP Verschlüssung │  - Verschlüsselt via dtls_srtp.vala            │
│  └──────┬───────────────┘                                                │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ dtls_srtp.vala  │  process_outgoing_data()                            │
│  │ - Keyframe-     │  - Erkennt Keyframes (VP8/VP9/H264)                 │
│  │   Detection     │  - Droppt Inter-Frames vor erstem Keyframe          │
│  │ - SRTP encrypt  │  - Verschlüsselt RTP-Payload                        │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ libnice         │  Nice.Agent.send_messages_nonblocking()             │
│  │ - ICE           │  - Sendet über ausgewählten Kandidaten              │
│  │ - UDP Socket    │  - STUN/TURN falls nötig                            │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│      [NETZWERK]                                                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Eingehender Medienfluss (Empfangen)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    EINGEHENDER AUDIO/VIDEO FLUSS                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│      [NETZWERK]                                                          │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ libnice         │  on_recv() Callback                                 │
│  │ - UDP Socket    │  - Empfängt verschlüsselte Pakete                   │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌──────────────────────┐                                                │
│  │ transport_params.vala│  on_recv()                                     │
│  │ - Weiterleitung an   │  - Ruft DTLS Handler auf                       │
│  │   DTLS Handler       │                                                │
│  └──────┬───────────────┘                                                │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ dtls_srtp.vala  │  process_incoming_data()                            │
│  │ - DTLS Demux    │  - Trennt DTLS-Handshake von Medien                 │
│  │ - SRTP decrypt  │  - Entschlüsselt RTP-Payload                        │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ stream.vala     │  on_recv_rtp_data()                                 │
│  │ - SDES Fallback │  - Optionale zweite Entschlüsselung                 │
│  │ - recv_rtp      │  - push_buffer() an appsrc                          │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ plugin.vala     │  on_rtp_pad_added()                                 │
│  │ - rtpbin        │  - Erkennt neue SSRC                                │
│  │ - Pad Linking   │  - Verbindet mit Decoder                            │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ codec_util.vala │  get_decode_bin()                                   │
│  │ - rtpvp8depay   │  - RTP-Depayloader                                  │
│  │ - vp8dec/opus   │  - Decoder                                          │
│  │ - videoconvert  │  - Format-Konvertierung                             │
│  └──────┬──────────┘                                                     │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────┐                                                     │
│  │ VIDEO:          │                                                     │
│  │ - videoflip     │  Rotiert nach Orientierung                          │
│  │ - VideoWidget   │  GTK-Anzeige                                        │
│  ├─────────────────┤                                                     │
│  │ AUDIO:          │                                                     │
│  │ - audiorate     │  Sample-Rate Anpassung                              │
│  │ - echoprobe     │  Echo-Referenz                                      │
│  │ - Lautsprecher  │  Audio-Ausgabe                                      │
│  └─────────────────┘                                                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

# 4. DETAILLIERTE DATEIANALYSE

## 4.1 stream.vala (946 Zeilen)

**Zweck:** Kern des RTP-Stream-Handlings - verbindet GStreamer mit Netzwerk.

### Wichtige Methoden

| Methode | Zeilen | Funktion |
|---------|--------|----------|
| `create()` | 92-192 | Erstellt alle GStreamer-Elemente |
| `on_new_sample()` | 329-427 | Sendet RTP-Pakete ans Netzwerk |
| `on_recv_rtp_data()` | 634-723 | Empfängt RTP-Pakete vom Netzwerk |
| `on_rtp_ready()` | ~800 | Fordert Keyframe an wenn bereit |
| `destroy()` | 497-620 | Räumt alles auf |

### DinoX-Verbesserungen

```vala
// Signal Handler IDs für sauberes Aufräumen (DinoX-Neu)
private ulong senders_changed_handler_id;
private ulong feedback_rtcp_handler_id;
private ulong send_rtp_new_sample_handler_id;
private ulong send_rtcp_new_sample_handler_id;

// AppSrc Stream Type gegen Segment-Warnungen (DinoX-Neu)
recv_rtp.stream_type = Gst.App.StreamType.STREAM;
recv_rtcp.stream_type = Gst.App.StreamType.STREAM;

// Element-Status-Synchronisation (DinoX-Neu)
pipe.add(send_rtp);
send_rtp.sync_state_with_parent();
```

---

## 4.2 transport_parameters.vala (539 Zeilen)

**Zweck:** ICE-Konnektivität und DTLS-Transport via libnice.

### Wichtige Methoden

| Methode | Zeilen | Funktion |
|---------|--------|----------|
| `TransportParameters()` | 140-200 | Erstellt ICE Agent und DTLS Handler |
| `send_datagram()` | 47-126 | Sendet verschlüsselte Pakete |
| `on_recv()` | 347-408 | Empfängt und entschlüsselt Pakete |
| `on_component_state_changed()` | 370-400 | Überwacht ICE-Status |

### DinoX-Verbesserungen (KRITISCH)

```vala
// DTLS Buffering - verhindert Paketverluste (DinoX-Neu)
private Gee.LinkedList<Bytes>? pending_packets = null;
private bool dtls_ready_notified = false;

public override void send_datagram(Bytes datagram) {
    if (dtls_srtp_handler != null) {
        // DINOX: Puffern wenn DTLS nicht bereit
        if (!dtls_srtp_handler.ready) {
            if (pending_packets == null) {
                pending_packets = new Gee.LinkedList<Bytes>();
            }
            if (pending_packets.size < 100) {
                pending_packets.add(datagram);
                debug("DTLS not ready, buffering packet");
            }
            return;
        }
        // ...
    }
}

// EAGAIN Rate-Limiting (DinoX-Neu)
private int64 last_eagain_warning = 0;
private int eagain_count = 0;
// Loggt nur einmal pro Sekunde statt bei jedem Fehler

// TURN Transport Support (DinoX-Neu)
Nice.RelayType relay_type = Nice.RelayType.UDP;
if (turn_service.transport == "tcp") {
    relay_type = Nice.RelayType.TCP;
} else if (turn_service.transport == "tls") {
    relay_type = Nice.RelayType.TLS;
}
```

---

## 4.3 dtls_srtp.vala (488 Zeilen)

**Zweck:** DTLS-Handshake und SRTP-Verschlüsselung.

### Wichtige Methoden

| Methode | Zeilen | Funktion |
|---------|--------|----------|
| `setup_dtls_connection_thread()` | 251-347 | DTLS-Handshake |
| `process_incoming_data()` | ~380 | SRTP-Entschlüsselung |
| `process_outgoing_data()` | 64-166 | SRTP-Verschlüsselung + Keyframe-Erkennung |

### DinoX-Verbesserungen (KRITISCH)

```vala
// Keyframe Tracking (DinoX-Neu)
private bool sent_first_video_keyframe = false;

public uint8[]? process_outgoing_data(uint component_id, uint8[] data) {
    // DINOX: Umfangreiche Keyframe-Erkennung
    bool is_video = (pt == 96 || pt == 97 || pt == 98 || pt == 102);
    bool is_keyframe = false;
    
    // H.264 NAL Unit Analyse
    if (pt == 102) {
        uint8 nal_type = data[payload_offset] & 0x1F;
        is_keyframe = (nal_type == 5 || nal_type == 7 || nal_type == 8);
    }
    
    // VP9 P-bit Analyse
    else if (pt == 98) {
        is_keyframe = (data[payload_offset] & 0x40) == 0;
    }
    
    // VP8 Frame Tag Analyse
    else if (pt == 96 || pt == 97) {
        is_keyframe = (frame_tag & 0x01) == 0;
    }
    
    // KRITISCH: Inter-Frames vor erstem Keyframe droppen!
    if (is_video && !sent_first_video_keyframe) {
        if (is_keyframe) {
            sent_first_video_keyframe = true;
            debug("FIRST KEYFRAME!");
        } else {
            debug("DROPPING pre-keyframe inter-frame");
            return null; // DROP!
        }
    }
}
```

---

## 4.4 Weitere Dateien

### plugin.vala (599 Zeilen)
- Erstellt Master GStreamer Pipeline mit rtpbin
- Device Monitoring für Mikrofon/Kamera-Wechsel
- Clock Lost Handling

### device.vala (626 Zeilen)
- Verwaltet physische Geräte
- Dynamische Bitrate-Anpassung (REMB)
- Dynamische Auflösungs-Skalierung

### codec_util.vala (453 Zeilen)
- Encoder/Decoder Pipeline-Beschreibungen
- Codec-spezifische Parameter
- Hardware-Encoder Erkennung (VAAPI, MSDK)

### voice_processor.vala (210 Zeilen)
- WebRTC Audio Processing Integration
- Echo-Unterdrückung (AEC)
- Rauschunterdrückung, AGC

---

# 5. DINO VS DINOX VERGLEICH

## 5.1 Zusammenfassung

| Feature | Original Dino | DinoX |
|---------|---------------|-------|
| Signal Handler Cleanup | ❌ Keine IDs gespeichert | ✅ IDs gespeichert, sauberes Disconnect |
| DTLS Packet Buffering | ❌ Pakete gehen verloren | ✅ Pakete werden gepuffert |
| Keyframe Detection | ❌ Keine | ✅ VP8, VP9, H.264 |
| Inter-Frame Dropping | ❌ Alle gesendet | ✅ Vor Keyframe gedroppt |
| TURN Transport | ❌ Nur UDP | ✅ UDP, TCP, TLS |
| EAGAIN Handling | ❌ Warning pro Fehler | ✅ Rate-Limited Logging |
| GStreamer stream_type | ❌ Nicht gesetzt | ✅ STREAM gesetzt |
| sync_state_with_parent | ❌ Nicht verwendet | ✅ Verwendet |

## 5.2 Code-Vergleich

### Signal Handler (stream.vala)

**Original Dino:**
```vala
// Verbindet ohne ID zu speichern
send_rtp.new_sample.connect(on_new_sample);
send_rtp.connect("signal::eos", on_eos_static, this);
```

**DinoX:**
```vala
// Speichert Handler ID für sauberes Cleanup
send_rtp_new_sample_handler_id = send_rtp.new_sample.connect(on_new_sample);
send_rtp_eos_handler_id = GLib.Signal.connect(send_rtp, "eos", 
    (GLib.Callback)on_eos_static, this);
```

### DTLS Buffering (transport_parameters.vala)

**Original Dino:**
```vala
// Sofort senden - Paketverlust wenn DTLS nicht bereit!
uint8[] encrypted = dtls_srtp_handler.process_outgoing_data(...);
agent.send_messages_nonblocking(...);
```

**DinoX:**
```vala
// Puffern wenn DTLS nicht bereit
if (!dtls_srtp_handler.ready) {
    pending_packets.add(datagram);
    if (!dtls_ready_notified) {
        dtls_ready_notified = true;
        check_dtls_ready.begin();
    }
    return;
}
```

### Keyframe Detection (dtls_srtp.vala)

**Original Dino:**
```vala
// Einfach verschlüsseln - keine Analyse
return srtp_session.encrypt_rtp(data);
```

**DinoX:**
```vala
// Umfangreiche Analyse
if (is_video && !sent_first_video_keyframe) {
    if (is_keyframe) {
        sent_first_video_keyframe = true;
    } else {
        return null; // DROP!
    }
}
return srtp_session.encrypt_rtp(data);
```

---

# 6. SIGNALISIERUNG (JINGLE)

## 6.1 Jingle Session Aufbau

```
┌───────────────────────────────────────────────────────────────────────┐
│                        JINGLE SIGNALISIERUNG                           │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  INITIATOR (Alice)                        RESPONDER (Bob)             │
│       │                                         │                     │
│       │  ─── session-initiate ───────────────►  │                     │
│       │      <jingle action="session-initiate"> │                     │
│       │        <content name="audio">           │                     │
│       │          <payload-type id="111"         │                     │
│       │                        name="opus"/>    │                     │
│       │          <transport ufrag="..."         │                     │
│       │                     pwd="...">          │                     │
│       │            <fingerprint>...</>          │                     │
│       │            <candidate .../>             │                     │
│       │          </transport>                   │                     │
│       │        </content>                       │                     │
│       │      </jingle>                          │                     │
│       │                                         │                     │
│       │  ◄─── session-accept ─────────────────  │                     │
│       │                                         │                     │
│       │  ◄───► transport-info (Trickle ICE) ───►│                     │
│       │        (Kandidaten werden ausgetauscht) │                     │
│       │                                         │                     │
│       ├─────────────────────────────────────────┤                     │
│       │         ICE Connectivity Check          │                     │
│       ├─────────────────────────────────────────┤                     │
│       │                                         │                     │
│       ├─────────────────────────────────────────┤                     │
│       │         DTLS Handshake                  │                     │
│       ├─────────────────────────────────────────┤                     │
│       │                                         │                     │
│       │  ◄═══════ ENCRYPTED MEDIA ═══════════►  │                     │
│       │                                         │                     │
└───────────────────────────────────────────────────────────────────────┘
```

## 6.2 Codec-Aushandlung

```
Angeboten (Initiator):
  VP8:96, VP9:98, H264:102, Opus:111

Ausgewählt (Responder):
  VP8:96, Opus:111  ← Erste gemeinsame Codecs
```

---

# 7. ICE/DTLS NEGOTIATION

## 7.1 Zeitliche Abfolge

```
ZEIT    EREIGNIS
────────────────────────────────────────────────────────────────────────
T=0     Nice.Agent erstellt
        → STUN Server konfiguriert
        → TURN Credentials gesetzt
        
T=1     agent.gather_candidates()
        → Host Kandidaten gefunden
        → STUN Request → Server Reflexive Kandidaten
        → TURN Allokation → Relay Kandidaten
        
T=2     session-initiate / session-accept
        → Kandidaten ausgetauscht
        → Fingerprints ausgetauscht
        
T=3     ICE Connectivity Checks
        → STUN Binding Requests
        → Kandidatenpaare getestet
        
T=4     component_state_changed(READY)
        → Bestes Paar ausgewählt
        → ICE verbunden
        
T=5     DTLS Handshake
        → ClientHello / ServerHello
        → Zertifikate ausgetauscht
        → Fingerprint verifiziert
        
T=6     SRTP Keys extrahiert
        → set_encryption_key()
        → set_decryption_key()
        
T=7     connection.ready = true
        → on_rtp_ready()
        → Keyframe angefordert
        
T=8     MEDIA FLIESST
        → Verschlüsselte RTP/RTCP Pakete
────────────────────────────────────────────────────────────────────────
```

## 7.2 DTLS Role Negotiation

```
Initiator (actpass)     Responder (active/passive)
      │                        │
      │  setup="actpass" ─────►│  → Ich kann beides
      │                        │
      │  ◄───── setup="active" │  → Ich bin Client
      │                        │
      │  → Ich bin SERVER      │  → DTLS CLIENT
      │                        │
      │  ◄── ClientHello ──────│
      │  ─── ServerHello ─────►│
      │  ◄── Finished ─────────│
      │  ─── Finished ────────►│
```

---

# 8. RACE CONDITIONS & TIMING

## 8.1 Race: DTLS Ready vs Keyframe

```
PROBLEM:

Zeit    DTLS Handler              Video Encoder
─────────────────────────────────────────────────────
T0      running=false             Produziert Inter-Frame
T1      running=false             Produziert Inter-Frame
T2      DTLS handshake startet    Produziert Inter-Frame
T3      DTLS handshake...         Produziert Inter-Frame  → VERWORFEN
T4      ready=true!               Produziert Inter-Frame  → VERWORFEN
T5      on_rtp_ready()            
T6      ForceKeyUnit ────────────►
T7                                Produziert KEYFRAME     → GESENDET!
T8                                Produziert Inter-Frame  → GESENDET


AUSWIRKUNG: 100-500ms Verzögerung bis Video erscheint
```

## 8.2 Race: push_recv_data Timing

```
PROBLEM:

Zeit    Stream.create()           Netzwerk (Eingehend)
─────────────────────────────────────────────────────
T0      create() startet          
T1      appsrc erstellt           Paket empfangen
T2      rtpbin verbunden          on_recv_rtp_data()
T3                                if (push_recv_data)  → FALSE!
T4                                → PAKET VERWORFEN
T5      push_recv_data = true     
T6      create() fertig           Paket empfangen
T7                                → Dieses wird verarbeitet


AUSWIRKUNG: Erste Pakete gehen verloren → möglicher Audio-Aussetzer
```

## 8.3 Race: SSRC Wechsel

```
PROBLEM (stream.vala Zeile ~660):

if (participant_ssrc != 0 && participant_ssrc != ssrc) {
    warning("Got second ssrc on stream, ignoring");
    return;  // ← ZWEITER SSRC WIRD IGNORIERT!
}


AUSWIRKUNG: Wenn Remote sein Gerät wechselt → KEIN AUDIO/VIDEO MEHR
```

---

# 9. BEKANNTE PROBLEME & URSACHEN

## 9.1 "Mal Sound, mal kein Sound, mal Video, mal kein Video"

| Symptom | Ursache | Datei/Zeile |
|---------|---------|-------------|
| Kein Video am Anfang | Warten auf Keyframe nach DTLS | dtls_srtp.vala |
| Video friert ein | Keyframe verloren, Decoder wartet | codec_util.vala |
| Kein Audio am Anfang | DTLS nicht bereit, Pakete gepuffert | transport_params.vala |
| Audio bricht ab | Clock lost, Pipeline Neustart | plugin.vala |
| Einseitiges Audio | Crypto Keys nicht symmetrisch | stream.vala |
| Knacksen/Aussetzer | EAGAIN Drops, Paketverlust | transport_params.vala |
| Echo/Rückkopplung | Falsche Delay-Schätzung | voice_processor.vala |

## 9.2 Kritische Code-Stellen

| Datei | Zeilen | Problem | Risiko |
|-------|--------|---------|--------|
| dtls_srtp.vala | 64-166 | Keyframe-Logik | KRITISCH |
| transport_params.vala | 47-126 | DTLS Buffering | KRITISCH |
| stream.vala | 634-723 | push_recv_data Timing | HOCH |
| stream.vala | ~660 | SSRC Wechsel ignoriert | HOCH |
| plugin.vala | ~250 | Clock Lost Handling | MITTEL |

---

# 10. DEBUG-ANLEITUNG

## 10.1 GStreamer Debug aktivieren

```bash
# Ausführlich (sehr viel Output)
export GST_DEBUG=rtpbin:5,appsrc:5,appsink:5,*enc:4,*dec:4,*pay:4,*depay:4

# Nur RTP
export GST_DEBUG=rtpbin:4,rtpsession:4

# Nur Encoder
export GST_DEBUG=vp8enc:5,opusenc:5
```

## 10.2 libnice Debug aktivieren

```bash
export G_MESSAGES_DEBUG=libnice
export NICE_DEBUG=all
```

## 10.3 Wichtige Log-Nachrichten

```
✅ ERFOLG:
"new_selected_pair_full" → ICE funktioniert
"component_state_changed to READY" → ICE verbunden
"Finished DTLS connection" → DTLS fertig
"FIRST KEYFRAME" → Video sollte jetzt erscheinen

⚠️ WARNUNG:
"DROPPING pre-keyframe inter-frame" → Normal, aber zu viele = Problem
"DTLS not ready, buffering packet" → Normal während Handshake
"Clock lost. Restarting" → Kurze Unterbrechung erwartet

❌ FEHLER:
"DTLS handshake failed" → Keine Verbindung möglich
"Got second ssrc, ignoring" → SSRC-Wechsel Problem
"No peer certs" → DTLS Zertifikat fehlt
```

---

# 11. EMPFEHLUNGEN

## 11.1 Kurzfristige Fixes

### Fix 1: SSRC Wechsel erlauben

```vala
// stream.vala - on_ssrc_pad_added()
// VORHER:
if (participant_ssrc != 0 && participant_ssrc != ssrc) {
    warning("Got second ssrc, ignoring");
    return;
}

// NACHHER:
if (participant_ssrc != 0 && participant_ssrc != ssrc) {
    debug("SSRC changed: %u -> %u, updating", participant_ssrc, ssrc);
    // Alten Pad entfernen, neuen akzeptieren
}
participant_ssrc = ssrc;
```

### Fix 2: Frühe Pakete puffern

```vala
// stream.vala - on_recv_rtp_data()
private Gee.LinkedList<Bytes>? early_packet_buffer = null;

public override void on_recv_rtp_data(Bytes bytes) {
    if (!push_recv_data) {
        // Puffern statt droppen
        if (early_packet_buffer == null) {
            early_packet_buffer = new Gee.LinkedList<Bytes>();
        }
        early_packet_buffer.add(bytes);
        return;
    }
    // Normale Verarbeitung...
}
```

### Fix 3: Keyframe Reset bei Reconnect

```vala
// dtls_srtp.vala
public void reset_for_reconnect() {
    sent_first_video_keyframe = false;
}
```

## 11.2 Langfristige Verbesserungen

1. **WebRTC-Style ICE Restart** - Bei Verbindungsproblemen automatisch ICE neu starten
2. **Adaptive Bitrate** - Besser auf Paketverluste reagieren
3. **Simulcast/SVC** - Mehrere Qualitätsstufen für Video
4. **Bandwidth Estimation** - TWCC (Transport Wide Congestion Control)

---

# 12. LIBNICE 0.1.23 ANALYSE

## 12.1 Build-Informationen

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    LIBNICE BUILD DETAILS                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Version:     0.1.23 (2025-11-26)                                       │
│  Build:       Von Source kompiliert am 6. Dezember 2025                 │
│  Library:     /usr/lib/x86_64-linux-gnu/libnice.so.10.15.0              │
│  Repository:  https://github.com/libnice/libnice                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## 12.2 Wichtige Änderungen in 0.1.23 für unser Projekt

### 🔴 KRITISCH für Audio/Video Stabilität

| Änderung | Relevanz für DinoX |
|----------|-------------------|
| **Avoid dropping packets in nicesink, retry instead** | 🔴 **KRITISCH** - Das war ein Hauptproblem! Bei Backpressure werden Pakete jetzt nicht mehr gedroppt sondern es wird Retry gemacht. Das erklärt einige unserer "mal geht, mal nicht" Probleme! |
| **Add buffer list support to nicesrc** | ⚠️ Verbesserte Pufferverwaltung beim Empfangen |
| **Add missing mutex in tcp-bsd socket** | 🔴 **KRITISCH** - Race Condition Fix für TCP Sockets (TURN TCP!) |
| **Reject invalid remote candidates with priority=0** | ⚠️ Verhindert fehlerhafte Kandidaten |
| **Defer task completion to final unlock** | ⚠️ Mutex-Fix für async Close - vermeidet Deadlocks |

### 🟡 WICHTIG - Neuere API

| Feature | Beschreibung |
|---------|-------------|
| `NICE_AGENT_OPTION_CLOSE_FORCED` | Neues API Flag - TURN Allokation sofort beenden ohne auf Response zu warten. Nützlich bei Verbindungsabbruch! |

## 12.3 Relevante Änderungen 0.1.22 (March 2024)

| Änderung | Relevanz |
|----------|----------|
| **Include TURN sockets in nice_agent_get_sockets()** | ⚠️ Vollständige Socket-Liste |
| **Set consent refresh timeout in line with RFC 7675** | ⚠️ Korrektes Timeout für Consent Checks |
| **Make padding be all zeros to conform to RFC8489** | ⚠️ STUN Compliance |

## 12.4 Relevante Änderungen 0.1.19-0.1.21

| Version | Änderung | Relevanz |
|---------|----------|----------|
| 0.1.19 | **RFC 7675 Consent Freshness** | 🔴 KRITISCH - Erkennt wenn Peer weg ist |
| 0.1.19 | Allow incoming connchecks before remote candidates set | ⚠️ Bessere Trickle-ICE Unterstützung |
| 0.1.19 | Improved ICE restart implementation | ⚠️ Stabilere Reconnects |
| 0.1.20 | Async DNS resolution for STUN/TURN | ⚠️ Non-blocking |
| 0.1.20 | Limit stored incoming checks | ⚠️ Memory-Schutz |

## 12.5 Historische Fixes (0.1.15-0.1.18)

| Version | Fix | Impact |
|---------|-----|--------|
| 0.1.18 | Accept receiving messages in multiple steps over TCP | ICE-TCP Stabilität |
| 0.1.18 | Use sendmmsg for multiple packets | Performance |
| 0.1.17 | Retry TURN deallocation on timeout | TURN Cleanup |
| 0.1.16 | Async closing of agent for TURN | Sauberer Shutdown |
| 0.1.15 | **Removal of global lock over all agents** | 🔴 KRITISCH - Keine Deadlocks mehr bei mehreren Agents! |
| 0.1.15 | Now drops packets from non-validated addresses | Sicherheit |

## 12.6 Warum 0.1.23 wichtig für uns ist

```
┌─────────────────────────────────────────────────────────────────────────┐
│               PROBLEMANALYSE: "Mal geht, mal nicht"                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  VORHER (ältere libnice):                                               │
│  ──────────────────────                                                 │
│  1. nicesink hat Pakete GEDROPPT bei Backpressure                       │
│     → Audio/Video Aussetzer                                             │
│                                                                         │
│  2. TCP Socket Race Condition (fehlender Mutex)                         │
│     → TURN TCP/TLS instabil                                             │
│                                                                         │
│  3. Globaler Lock über alle Agents                                      │
│     → Deadlocks bei mehreren Streams                                    │
│                                                                         │
│  JETZT (0.1.23):                                                        │
│  ───────────────                                                        │
│  1. nicesink macht RETRY statt DROP                                     │
│     → Keine zufälligen Aussetzer mehr                                   │
│                                                                         │
│  2. TCP Mutex korrekt                                                   │
│     → TURN TCP/TLS stabil                                               │
│                                                                         │
│  3. Kein globaler Lock                                                  │
│     → Multi-Stream sicher                                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## 12.7 Empfehlung: NICE_AGENT_OPTION_CLOSE_FORCED nutzen

Das neue Flag `NICE_AGENT_OPTION_CLOSE_FORCED` kann bei Verbindungsabbrüchen helfen:

```vala
// transport_parameters.vala - Bei Agent Erstellung hinzufügen
Nice.Agent agent = new Nice.Agent.full(
    main_context,
    Nice.Compatibility.RFC5245,
    Nice.AgentOption.CLOSE_FORCED  // NEU in 0.1.23!
);
```

**Wann verwenden:**
- Bei schnellem Beenden eines Anrufs
- Wenn TURN Server nicht antwortet
- Bei Netzwerk-Timeout

## 12.8 Commit-Referenz

Der wichtige Commit für Task-Completion-Fix:
```
Commit: 4f16fcae8a2e09b16bdcdd0753b1066534138161
Autor: ocrete
Datum: November 2025
Beschreibung: "agent: Defer task completion to final unlock"
              Vermeidet Mutex-Release an falschen Stellen
```

---

# 13. FAZIT

## Was DinoX besser macht als Original Dino:

| Bereich | Verbesserung |
|---------|--------------|
| Stabilität | DTLS-Buffering verhindert Paketverluste |
| Video-Qualität | Keyframe-Detection sorgt für sauberen Start |
| Debug | Umfangreiches Logging für Diagnose |
| Code-Qualität | Signal Handler werden sauber verwaltet |
| Flexibilität | TURN TCP/TLS Support |
| **libnice** | **0.1.23 von Source - neueste Fixes!** |

## Verbleibende Probleme:

| Problem | Status |
|---------|--------|
| SSRC-Wechsel wird ignoriert | ❌ Noch nicht behoben |
| Frühe Pakete werden gedroppt | ❌ Noch nicht behoben |
| Clock Lost kann unterbrechen | ⚠️ Teilweise behoben |

## libnice 0.1.23 Fixes:

| Fix | Status |
|-----|--------|
| nicesink Retry statt Drop | ✅ Behoben durch libnice Upgrade |
| TCP Socket Mutex | ✅ Behoben durch libnice Upgrade |
| Consent Freshness (RFC 7675) | ✅ Behoben durch libnice Upgrade |
| Global Lock entfernt | ✅ Bereits seit 0.1.15 |

---

*Letzte Aktualisierung: 12. Dezember 2025*
*libnice: 0.1.23 (kompiliert 6. Dez 2025)*
