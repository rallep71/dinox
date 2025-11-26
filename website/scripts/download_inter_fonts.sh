#!/usr/bin/env bash
set -euo pipefail

echo "Downloading Inter fonts into website/fonts..."
mkdir -p website/fonts

# Attempt 1: Download Inter release ZIP from GitHub
RELEASE="v3.19"
TMPZIP="/tmp/inter.zip"
URL="https://github.com/rsms/inter/releases/download/${RELEASE}/Inter-${RELEASE}.zip"

echo "Attempting to fetch Inter $RELEASE from $URL"
DOWNLOAD_OK=0
if command -v curl >/dev/null 2>&1; then
  if curl -L -f -o "$TMPZIP" "$URL"; then
    DOWNLOAD_OK=1
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q -O "$TMPZIP" "$URL"; then
    DOWNLOAD_OK=1
  fi
fi

if [ "$DOWNLOAD_OK" -eq 1 ]; then
  echo "Download seems successful, attempting to extract .woff2 files..."
  if command -v unzip >/dev/null 2>&1; then
    unzip -o "$TMPZIP" '*.woff2' -d website/fonts || true
    echo "Fonts extracted to website/fonts"
  else
    echo "unzip not available; can't extract ZIP. Falling back to Google Fonts method."
    DOWNLOAD_OK=0
  fi
fi

# If GitHub release download fails for any reason, fallback to Google Fonts CSS to fetch .woff2 files directly
if [ "$DOWNLOAD_OK" -eq 0 ]; then
  echo "Falling back to Google Fonts CSS approach to fetch Inter woff2 files."
  # Choose weights we need
  WEIGHTS="300;400;500;700;800"
  GOOGLE_CSS_URL="https://fonts.googleapis.com/css2?family=Inter:wght@${WEIGHTS}&display=swap"

  echo "Requesting CSS from $GOOGLE_CSS_URL"
  # Use a modern User Agent to encourage Google Fonts to return woff2 format
  UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36"
  CSS_FILE="/tmp/inter-google.css"
  if command -v curl >/dev/null 2>&1; then
    curl -A "$UA" -f -L -o "$CSS_FILE" "$GOOGLE_CSS_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget --header="User-Agent: $UA" -q -O "$CSS_FILE" "$GOOGLE_CSS_URL"
  else
    echo "Install curl or wget to download from Google Fonts." >&2
    exit 1
  fi

  echo "Parsing CSS for woff2 URLs and downloading files..."
  # Extract unique woff2 URLs
  urls=$(grep -o "https://[^\"']*\\.woff2" "$CSS_FILE" | sort -u || true)
  # Support WOFF2 and sometimes TTF fallback when woff2 unavailable
  if [ -z "$urls" ]; then
    # Try finding TTF/WOFF URLs (fallback)
    urls=$(grep -o "https://[^\"']*\\.ttf" "$CSS_FILE" | sort -u || true)
  fi
  if [ -z "$urls" ]; then
    echo "No woff2 urls found in CSS. Something went wrong with the CSS fetch or format." >&2
  fi
  # Attempt to extract the Latin (U+0000-00FF) unicode-range URL for a set of weights and name them
  declare -A weight_files
  weight_files[300]="Inter-Thin.woff2"
  weight_files[400]="Inter-Regular.woff2"
  weight_files[500]="Inter-Medium.woff2"
  weight_files[700]="Inter-SemiBold.woff2"
  weight_files[800]="Inter-Bold.woff2"

  for w in 300 400 500 700 800; do
    # Parse CSS, find @font-face block with font-weight: w and unicode-range: latin, extract URL
    url=$(awk -v weight="$w" 'BEGIN{RS="}";} $0 ~ "font-weight: "weight && $0 ~ "unicode-range: U\\+0000-00FF" { if (match($0, /url\(([^)]+)\)/, a)) print a[1] }' "$CSS_FILE" | head -n1)
    if [ -n "$url" ]; then
      fname=$(basename "$url")
      outname="website/fonts/${weight_files[$w]}"
      echo "Downloading weight=$w $url -> $outname"
    if command -v curl >/dev/null 2>&1; then
      curl -f -L -o "$outname" "$url" || echo "Failed to download $url"
      elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$outname" "$url" || echo "Failed to download $url"
      fi
      fi
  done
  echo "Google Fonts fallback complete. Check website/fonts/ for files."
  # Optionally cleanup non-Inter-*.woff2 files (hashed names) to avoid duplicates
  echo "Cleaning up temporary font files..."
  shopt -s extglob || true
  for f in website/fonts/*; do
    case "$f" in
      website/fonts/Inter-*.woff2|website/fonts/README.md) ;; # keep
      *) rm -f "$f" ;;
    esac
  done
  echo "Cleanup complete. Remaining files:" && ls -la website/fonts
fi

echo "Done. Remember to commit website/fonts/* to your repo if self-hosting." 

echo "Done. Remember to commit website/fonts/* to your repo if self-hosting." 
