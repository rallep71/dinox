# DinoX Website

Professionelle Website für DinoX - Moderner XMPP Messenger für Linux.

## Struktur

```
website/
├── index.html          # Hauptseite
├── css/
│   └── style.css       # Styles
├── js/
│   └── main.js         # JavaScript
├── assets/             # Bilder, Icons, Screenshots
├── docs/               # Dokumentationsseiten
└── README.md           # Diese Datei
```

## Features

- ✅ Responsive Design (Mobile-first)
- ✅ Dark/Light Mode mit System-Präferenz
- ✅ Smooth Scrolling & Animationen
- ✅ Zero Dependencies (Vanilla JS/CSS)
- ✅ Schnell & Lightweight
- ✅ SEO-optimiert
- ✅ Barrierefreundlich

## Deployment

### GitHub Pages

1. Repository erstellen:
```bash
cd /media/linux/SSD128/xmpp
git subtree push --prefix website origin gh-pages
```

2. GitHub Pages aktivieren:
   - Repository Settings → Pages
   - Source: gh-pages branch
   - Custom Domain: dinox.handwerker.jetzt

### GitHub Actions

Dieses Repository enthält jetzt einen GitHub Actions Workflow `.github/workflows/gh-pages.yml`, der automatisch den Inhalt von `website/` auf den Branch `gh-pages` deployed, wenn auf `master` gepusht wird.

Um sicherzustellen, dass dein CNAME funktioniert, verwende die Datei `website/CNAME` im Repo (bereits mit dinox.handwerker.jetzt gesetzt). Wenn du das Repo für GitHub Pages verwendest, wird GitHub Pages auch automatisch dein `CNAME` registrieren.

3. DNS konfigurieren:
```
A Record: dinox.handwerker.jetzt → 185.199.108.153
A Record: dinox.handwerker.jetzt → 185.199.109.153
A Record: dinox.handwerker.jetzt → 185.199.110.153
A Record: dinox.handwerker.jetzt → 185.199.111.153
CNAME Record: www.dinox.handwerker.jetzt → rallep71.github.io
```

### Statischer Webserver (nginx)

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name dinox.handwerker.jetzt www.dinox.handwerker.jetzt;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name dinox.handwerker.jetzt www.dinox.handwerker.jetzt;
    
    # SSL Certificate (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/dinox.handwerker.jetzt/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/dinox.handwerker.jetzt/privkey.pem;
    
    root /var/www/dinox.handwerker.jetzt;
    index index.html;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
}
```

### Apache

```apache
<VirtualHost *:80>
    ServerName dinox.handwerker.jetzt
    ServerAlias www.dinox.handwerker.jetzt
    Redirect permanent / https://dinox.handwerker.jetzt/
</VirtualHost>

<VirtualHost *:443>
    ServerName dinox.handwerker.jetzt
    ServerAlias www.dinox.handwerker.jetzt
    
    DocumentRoot /var/www/dinox.handwerker.jetzt
    
    # SSL
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/dinox.handwerker.jetzt/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/dinox.handwerker.jetzt/privkey.pem
    
    # Security Headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    
    # Caching
    <FilesMatch "\.(js|css|png|jpg|jpeg|gif|ico|svg)$">
        Header set Cache-Control "max-age=31536000, public"
    </FilesMatch>
    
    # Compression
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
</VirtualHost>
```

## Assets TODO

Folgende Assets müssen noch hinzugefügt werden:

1. **Logo & Icons:**
   - `assets/dinox-logo.svg` - Haupt-Logo
   - `assets/icon.svg` - Favicon
   - `assets/dinox-icon-*.png` - Verschiedene Größen

2. **Screenshots:**
   - `assets/screenshot-main.png` - Hero-Screenshot
   - `assets/screenshot-chat.png` - Chat-Ansicht
   - `assets/screenshot-call.png` - Videocall
   - `assets/screenshot-preferences.png` - Einstellungen

3. **Optional:**
   - `assets/og-image.png` - Open Graph (1200x630px)
   - `assets/twitter-card.png` - Twitter Card (1200x600px)

## Development

Lokaler Server:
```bash
cd website
python3 -m http.server 8000
# Öffne http://localhost:8000
```

Oder mit Live-Reload:
```bash
npm install -g live-server
cd website
live-server
```

## Anpassungen

### Farben ändern
Editiere CSS-Variablen in `css/style.css`:
```css
:root {
    --primary-color: #3584e4;
    --primary-hover: #1c71d8;
    /* ... */
}
```

### Inhalte ändern
Editiere `index.html` direkt.

### Neue Seiten hinzufügen
Erstelle neue HTML-Dateien und verlinke sie in der Navigation.

## Performance

- ✅ Keine externen Abhängigkeiten
- ✅ Minimales CSS/JS
- ✅ Optimierte Bilder (WebP empfohlen)
- ✅ Lazy Loading für Bilder
- ✅ Caching-Header

## Browser-Support

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Opera 76+

## Lizenz

Website-Code: MIT License
DinoX Software: GPLv3
