# Strategie zur Beschaffung von Tor Bridges (Anti-Zensur)

**Status:** Entwurf / Analyse
**Datum:** 9. Januar 2026
**Kontext:** Umgehung von Zensurmaßnahmen (DPI, DNS-Poisoning, IP-Blocking) für DinoX.

## 1. Problemstellung
In restriktiven Netzwerken (China, Iran, Russland, Firmennetzwerke) sind:
1.  Die öffentlichen Tor-Relays (Guard Nodes) IP-blockiert.
2.  Die Webseite `torproject.org` via DNS oder IP blockiert.
3.  DNS-Anfragen (Port 53) werden überwacht oder manipuliert (Poisoning).

Ziel ist es, dem Nutzer funktionierende **Bridges** (Brückenknoten, insb. `obfs4`) bereitzustellen, ohne dass er manuell eine blockierte Webseite aufrufen muss.

## 2. Lösungsansätze (Analyse)

### A. Tor Moat API (via Domain Fronting / Meek)
Dies ist der "Gold-Standard", den der Tor Browser verwendet.
*   **Funktionsweise:** Der Client sendet eine Anfrage an einen erlaubten CDN-Endpunkt (z.B. Azure, Fastly), aber mit dem HTTP-Host-Header `bridges.torproject.org`.
*   **Vorteil:** Extrem schwer zu blockieren, da der Censor das gesamte CDN blockieren müsste.
*   **Nachteil (Implementierung):**
    *   Erfordert **CAPTCHA**-Interaktion (Nutzer muss Bild lösen).
    *   Benötigt `json-glib` (JSON-Parsing).
    *   Komplexer HTTP-Handshake in Vala (Domain Fronting).

### B. DNS over HTTPS (DoH) - Nutzer-Vorschlag
Abfragen von Informationen über verschlüsseltes HTTP (JSON-Format) statt UDP Port 53.
*   **Anwendungsfall 1: Auflösung blockierter Domains.**
    *   Wenn wir Bridges auf `brücken.dinox.org` hosten, wird die Domain oft per DNS gesperrt.
    *   Lösung: DoH (z.B. Cloudflare/Google) nutzt HTTPS zu einer unblockierten IP, um die echte IP von `brücken.dinox.org` zu erhalten.
*   **Anwendungsfall 2: Daten via TXT Records.**
    *   Idee: Bridges direkt in DNS TXT Records speichern.
    *   *Problem:* Bridge-Lines sind lang (>100 Zeichen), DNS ist für kleine Pakete optimiert. TXT-Records sind öffentlich und leicht von Zensoren scrapbar.
*   **Bewertung:** DoH ist ein exzellentes *Hilfsmittel*, um Verbindungsendpunkte zu finden, aber kein alleiniger Verteilungsmechanismus für geheime Bridges.

### C. Bundled Bridges
*   **Idee:** Wir liefern 2-3 Bridges fest im App-Code mit.
*   **Vorteil:** Funktioniert "Out of the Box".
*   **Nachteil:** Diese Bridges werden schnell erkannt und blockiert. Nur als "Nothilfe" brauchbar.

## 3. Empfohlener Plan: "DinoX Bridge Fetcher"

Wir sollten einen stufenweisen Ansatz verfolgen.

### Phase 1: Manuelle Eingabe & Bundled Fallback (Sofort)
1.  **UI:** Textfeld in den Einstellungen für "Custom Bridges".
2.  **Bundled:** 2-3 Default-Bridges (obfs4) fest im Code hinterlegen.

### Phase 2: "Smart Fetcher" via DoH (Mittelfristig)
Wir nutzen DoH, um eine Zensur unserer Verteilungs-Infrastruktur zu umgehen.

*   **Ablauf:**
    1.  DinoX fragt via DoH (Cloudflare/Quad9) nach der IP von `bridges.dinox.org` (oder einem GitHub Raw Pointer).
    2.  DinoX lädt eine Liste von Bridges via HTTPS von dort.
    3.  Warum DoH? Weil der einfache DNS-Lookup oft das erste ist, was blockiert wird ("DNS Poisoning").

### Phase 3: Volle Moat-Integration (Langfristig)
Implementierung der offiziellen Tor API mit Captcha-Support im UI.

## 4. Technische Implementierung (Phase 2 - DoH)

**Benötigte Libraries:**
*   `libsoup-3.0` (Vorhanden) - Für HTTPS.
*   `json-glib-1.0` (Neu) - Für DoH JSON Responses und Moat.

**Konzept (Vala):**

```vala
// Pseudocode für einen DoH-Resolver Helper
public async string resolve_via_doh(string hostname) {
    var session = new Soup.Session();
    // Cloudflare DNS-over-HTTPS Endpoint
    var uri = "https://cloudflare-dns.com/dns-query?name=%s&type=A".printf(hostname);
    var msg = new Soup.Message("GET", uri);
    msg.request_headers.append("Accept", "application/dns-json");
    
    // Sende Request... Parsen des JSON... Rückgabe der IP.
    // Falls Cloudflare blockiert ist, Fallback auf Google (8.8.8.8) DoH.
}
```

## 5. Nächste Schritte

1.  `json-glib` zu `meson.build` hinzufügen (als Dependency).
2.  `TorSettingsPage` erweitern: Eingabefeld für "Bridge Line".
3.  Experimentell: Einen einfachen Fetcher bauen, der eine Liste von einer URL lädt (via DoH resolved).

