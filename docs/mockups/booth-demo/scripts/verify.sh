#!/usr/bin/env bash
# Checks a rendered booth loop: 1920x1080, 30 fps, H.264, silent, 30–36 s, last frame matches the first.
# Usage: scripts/verify.sh roamory-how-it-works.mp4
set -u
mp4=${1:?usage: verify.sh <mp4>}
[ -s "$mp4" ] || { echo "✗ $mp4 missing or empty"; exit 1; }
fail=0
v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of csv=p=0 "$mp4")
[ "$v" = "h264,1920,1080,30/1" ] || { echo "✗ video stream is $v, want h264,1920,1080,30/1"; fail=1; }
a=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$mp4")
[ -z "$a" ] || { echo "✗ has an audio stream"; fail=1; }
d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp4")
awk -v d="$d" 'BEGIN { exit !(d >= 29.9 && d <= 36.1) }' || { echo "✗ duration $d s, want 30–36"; fail=1; }

# Seam: the first and last frames must match (scripts/seam.sh checks the whole frame, Roamy and the phone).
tmp=$(mktemp -d)
ffmpeg -v error -i "$mp4" -frames:v 1 "$tmp/first.png"
ffmpeg -v error -sseof -0.5 -i "$mp4" -update 1 "$tmp/last.png"
bash "$(dirname "$0")/seam.sh" "$tmp/first.png" "$tmp/last.png" || fail=1
rm -rf "$tmp"

size=$(stat -f%z "$mp4")
echo "size $((size / 1024 / 1024)) MB, duration $d s"
[ "$size" -le 26214400 ] || echo "! over 25 MB: don't commit the MP4"
[ $fail -eq 0 ] && echo "✓ $mp4"
exit $fail
