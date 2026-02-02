# Barrierefreiheit – Checkliste & Prüfprotokoll (Nachweis)

Stand: 20. Dezember 2025  
Projekt: DinoX Website (statische Website unter `docs/`)

## 1) Zweck / Geltungsbereich
Dieses Dokument dient als interner Nachweis über durchgeführte Barrierefreiheits-Prüfungen und umgesetzte Maßnahmen.

**Geprüfte Seiten (lokal):**
- `index.html`
- `privacy.html`
- `donations.html`
- `impressum.html`
- `datenschutz.html`
- `spenden.html`

**Zielniveau:** WCAG 2.1 AA als Referenz (im Kontext EN 301 549).

## 2) Prüfumgebung
- Datum: 20. Dezember 2025
- Website: lokal via `python3 -m http.server` (HTTP auf `http://127.0.0.1:8000/`)
- Automatisierte Prüfung: `pa11y` (via `npx`) gegen lokale URLs
- Manuelle Prüfung: Tastaturbedienung (Tab/Shift+Tab/Enter/Space/Esc)

## 3) Prüfmethode (Kurz)
### 3.1 Manuelle Tastaturprüfung (Keyboard-only)
**Testschritte (Startseite exemplarisch, analog für Unterseiten):**
- Skip-Link: `Tab` → Skip-Link sichtbar → `Enter` → Fokus springt in den Hauptinhalt
- Navigation/Mobile-Menü: Öffnen/Schließen per Tastatur, Fokusfluss beim Öffnen/Schließen, `Esc` schließt
- Karussell/Slider: Dots per Tab erreichbar, per Enter/Space bedienbar, keine Auto-Rotation
- Screenshot-Galerie/Lightbox: Öffnen per Tastatur, Fokus im Dialog gefangen (Focus Trap), `Esc` schließt, Fokus kehrt korrekt zurück
- Copy-to-clipboard: Button wird per Fokus sichtbar, per Enter/Space nutzbar
- Back-to-top: per Tab erreichbar, per Enter/Space nutzbar

**Ergebnis:** Bedienung war durchgängig möglich und „gut bedienbar“ (Rückmeldung aus manuellem Test).

### 3.2 Automatisierte Prüfung (pa11y)
**Tool:** `npx pa11y` 

**Ergebnis (20. Dezember 2025):**
- `index.html`: No issues found
- `privacy.html`: No issues found
- `donations.html`: No issues found
- `impressum.html`: No issues found
- `datenschutz.html`: No issues found
- `spenden.html`: No issues found

Hinweis: Automatisierte Tools finden nicht alle Probleme (insb. Screenreader-Nutzung, komplexe Bedienmuster, inhaltliche Qualität von Alternativtexten, etc.).

## 4) Umgesetzte Maßnahmen (Auszug)
(Details sind im Git-Verlauf ersichtlich; hier nur die wichtigsten Kategorien.)

- **Tastaturbedienbarkeit:** Interaktive Elemente sind per Tab erreichbar und per Enter/Space bedienbar.
- **Sichtbarer Fokus:** Fokus ist sichtbar und Hover-Zustände wurden für Tastatur per `:focus-visible` ergänzt.
- **Dialog/Modalität:** Lightbox ist als echtes Modal umgesetzt (inkl. Fokus-Management, Focus Trap, Fokus-Restore).
- **Mobile-Menü:** Fokus wird beim Öffnen ins Menü gesetzt; Tab-Fokus wird innerhalb gehalten; `Esc` schließt; Fokus kehrt zum Toggle zurück.
- **Bewegung/Animationen:** `prefers-reduced-motion` wird respektiert; kein „unsichtbar aber fokussierbar“ durch Fade-in.
- **Links / neue Tabs:** Keine unerwarteten Kontextwechsel; bei explizitem `target="_blank"` wird `rel` gehärtet und ein SR-Hinweis ergänzt.
- **Sprache:** `lang` gesetzt; deutsche Einsprengsel (z.B. Eigennamen/Adresse) markiert.

## 5) Checkliste (WCAG 2.1 AA – praxisnah)
Status: ✅ erledigt / 🟡 teilweise / ⬜ offen

### Wahrnehmbar (Perceivable)
- ✅ Kontraste (Text/Links) im Dark-Theme geprüft/behoben (pa11y: keine Findings)
- ✅ Alternativtexte für wesentliche Bilder vorhanden (Startseite)
- ✅ Reduzierte Bewegung (`prefers-reduced-motion`) beachtet

### Bedienbar (Operable)
- ✅ Tastaturbedienung ohne Maus (Navigation, Slider, Lightbox, Copy, Back-to-top)
- ✅ Keine Tab-Fallen; Fokus bleibt in Dialog/Mobile-Menü wenn geöffnet
- ✅ Sichtbarer Fokus (inkl. `:focus-visible` Parität zu Hover)
- ✅ Keine unerwarteten neuen Tabs

### Verständlich (Understandable)
- ✅ Konsistente Beschriftungen/ARIA für zentrale Controls (Menü, Theme, Lightbox)
- ✅ Skip-Link vorhanden und fokussiert Ziel

### Robust (Robust)
- ✅ Semantische Controls (Buttons/Links) statt klickbarer Container
- ✅ Buttons explizit `type="button"` (robuster gegen spätere Form-Änderungen)

## 6) Offene / empfohlene Restprüfungen (manuell)
Für einen „vollständigen“ Nachweis im engeren Sinne werden zusätzlich empfohlen:
- ⬜ Screenreader-Smoke-Test (z.B. NVDA/VoiceOver): Fokusansagen, Dialogansage, Reihenfolge
- ⬜ Zoom/Reflow: 200% und 400% (Mobile/Responsive) – keine abgeschnittenen Inhalte, keine unbedienbaren Bereiche
- ⬜ Kontrast-Spotcheck für Sonderzustände (Disabled/Visited/Focus auf Spezialkomponenten)

## 7) Fazit
Für die geprüften Seiten wurden Tastaturbedienbarkeit, Fokusführung und zentrale Interaktionen (Menü/Lightbox/Slider/Copy/Scroll) so umgesetzt, dass sie in manuellen Tests gut bedienbar sind. Der automatisierte pa11y-Scan meldet zum Stand 20. Dezember 2025 keine Probleme.
