# DinoX WebRTC Video Calls - Status Dokumentation

**Datum:** 3. Dezember 2025  
**Branch:** feature/video-codecs  
**Autor:** GitHub Copilot

## 📊 Aktueller Status

### ✅ FUNKTIONIERT
- **Videoanrufe funktionieren** mit Monal (iOS) und Conversations (Android).
- **Mehrere aufeinanderfolgende Anrufe** funktionieren zuverlässig.
- **Audio** funktioniert stabil (Opus, PT=111).
- **VP8 Video** (PT=96) funktioniert.
- **VP9 Video** (PT=98) funktioniert (Fixes in `codec_util.vala`).
- **H264 Video** (PT=100) funktioniert.

### 🛠️ Code-Bereinigung & Fixes (03.12.2025)
- **Leichen entfernt:** Unvollständige `webrtcbin`-Implementierung (`webrtc_call.vala`, `webrtc_transport.vala` etc.) wurde gelöscht.
- **Architektur bereinigt:** `WebRTCModule` kümmert sich nur noch um die Aushandlung (Negotiation) und nutzt für den Transport die stabilen `Stream`-Klassen.
- **Pipeline-Fix:** "Erster Anruf kein Video"-Problem adressiert durch Hinzufügen von `sync_state_with_parent()` in `Stream.vala` und `Device.vala`. Dies stellt sicher, dass Elemente korrekt starten, auch wenn die Pipeline bereits läuft.

---

## 🔧 Technische Details

### Hybrid-Architektur
Wir nutzen einen hybriden Ansatz für maximale Kompatibilität:
1.  **Negotiation (`WebRTCModule`):** Priorisiert VP9/VP8 korrekt für WebRTC-Clients.
2.  **Transport (`Stream`):** Nutzt Dinos bewährte Jingle-ICE-UDP Implementierung mit manueller GStreamer-Pipeline.

### Wichtige Codec-Einstellungen (`codec_util.vala`)
- **VP9:** `deadline=1`, `cpu-used=4`, `keyframe-max-dist=30`, `picture-id-mode=2` (15-bit).
- **VP8:** `keyframe-max-dist=30`.

## 🔜 Nächste Schritte
- **Phase 3:** Datenbank-Verschlüsselung (`omemo.db`) implementieren (siehe `PHASE_3_IMPLEMENTATION_PLAN.md`).
