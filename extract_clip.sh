#!/usr/bin/env bash
# Extract an audio clip from a Tim Dillon Show episode via the podcast RSS feed.
# Usage: ./extract_clip.sh <episode_number> <start_time> <end_time>
# Example: ./extract_clip.sh 488 32:46 34:00

set -euo pipefail

EPISODE="${1:?Usage: $0 <episode_number> <start_time> <end_time>}"
START="${2:?Provide start time (e.g. 32:46)}"
END="${3:?Provide end time (e.g. 34:00)}"

RSS_URL="https://audioboom.com/channels/5093219.rss"
SAFE_START=$(echo "$START" | tr ':' 'm')s
SAFE_END=$(echo "$END" | tr ':' 'm')s
OUTPUT="tim_dillon_ep${EPISODE}_${SAFE_START}_to_${SAFE_END}.mp3"
FULL_FILE="tim_dillon_ep${EPISODE}_full.mp3"

echo "Fetching RSS feed..."
MP3_URL=$(python3 -c "
import urllib.request, ssl, xml.etree.ElementTree as ET
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request('${RSS_URL}', headers={'User-Agent': 'Mozilla/5.0'})
resp = urllib.request.urlopen(req, context=ctx, timeout=30)
root = ET.fromstring(resp.read())
for item in root.iter('item'):
    title = item.find('title')
    if title is not None and '${EPISODE}' in (title.text or '').split(' -')[0]:
        enc = item.find('enclosure')
        if enc is not None:
            print(enc.get('url'))
            break
")

if [ -z "$MP3_URL" ]; then
    echo "Error: Episode $EPISODE not found in RSS feed."
    exit 1
fi

echo "Found episode. Downloading full audio..."
python3 -c "
import urllib.request, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
req = urllib.request.Request('${MP3_URL}', headers={'User-Agent': 'Mozilla/5.0'})
resp = urllib.request.urlopen(req, context=ctx, timeout=600)
total = 0
with open('${FULL_FILE}', 'wb') as f:
    while True:
        chunk = resp.read(131072)
        if not chunk:
            break
        f.write(chunk)
        total += len(chunk)
print(f'Downloaded {total/(1024*1024):.1f}MB')
"

echo "Extracting clip from $START to $END..."
ffmpeg -y -i "$FULL_FILE" -ss "00:$START" -to "00:$END" -c copy "$OUTPUT" 2>/dev/null

echo "Cleaning up full file..."
rm -f "$FULL_FILE"

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null)
SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')

echo ""
echo "Done! Clip saved to: $OUTPUT"
echo "Duration: ${DURATION}s | Size: $SIZE"
