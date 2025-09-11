#!/usr/bin/env bash
set -euo pipefail

# Usage: ./extract_and_update.sh <channel_key> <page_or_url>
key="$1"
page_or_url="$2"
repo_root="$GITHUB_WORKSPACE"
playfile="$repo_root/in_custom.m3u"
datadir="$repo_root/.tmp_data"
mkdir -p "$datadir"

echo "[extract] key=$key page=$page_or_url"

candidate=""

# If page_or_url already is an m3u8, use it directly
if [[ "$page_or_url" =~ \.m3u8 ]]; then
  candidate="$page_or_url"
else
  # Try yt-dlp first (best chance to find hidden streams)
  if command -v yt-dlp >/dev/null 2>&1; then
    candidate="$(yt-dlp -g "$page_or_url" 2>/dev/null | head -n1 || true)"
  fi

  # Fallback: simple HTML/JS scan for m3u8
  if [ -z "$candidate" ]; then
    tmpf="$(mktemp)"
    curl -fsSL "$page_or_url" -o "$tmpf" || true
    candidate="$(grep -oE 'https?://[^\"'\'']+\.m3u8[^\"'\'']*' "$tmpf" | head -n1 || true)"
    rm -f "$tmpf"
  fi
fi

if [ -z "$candidate" ]; then
  echo "[extract] No m3u8 candidate found for $key"
  exit 2
fi

echo "[extract] candidate=$candidate"

# Optional quick HEAD test (keeps going even if not 200)
http_code="$(curl -s -I -L -A 'Mozilla/5.0' --max-time 12 -o /dev/null -w '%{http_code}' "$candidate" || echo "000")"
echo "[extract] http_code=$http_code"

# Save candidate for inspection
echo "$candidate" > "$datadir/${key}-m3u8.txt"

# Replace the first URL after #CHANNEL:key in the playlist
tmpfile="$(mktemp)"
awk -v key="#CHANNEL:${key}" -v new="$candidate" '
{ print $0
  if($0==key && done==0){
    if(getline nxt){
      if(nxt ~ /^https?:\/\//){ print new } else { print nxt }
    }
    done=1
  }
}' "$playfile" > "$tmpfile"

mv "$tmpfile" "$playfile"

echo "[extract] playlist updated for $key -> $candidate"
echo "$candidate"
