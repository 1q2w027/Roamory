#!/usr/bin/env bash
# Is the loop seam invisible? Compares the first and last frames (PNGs) as a whole and where the eye looks:
# Roamy and the phone, both at their frame-0 home spots. Whole-frame SSIM alone is too forgiving on a dark frame.
# Usage: scripts/seam.sh first.png last.png
set -u
first=${1:?usage: seam.sh first.png last.png}
last=${2:?usage: seam.sh first.png last.png}
ssim() { ffmpeg -i "$first" -i "$last" -lavfi "[0]crop=$1[a];[1]crop=$1[b];[a][b]ssim" -f null - 2>&1 | sed -n 's/.*All:\([0-9.]*\).*/\1/p'; }
fail=0
# name, crop w:h:x:y, minimum SSIM (real seam measured 0.996 / 0.978 / 0.994)
while read -r name crop min; do
  s=$(ssim "$crop")
  if awk -v s="${s:-0}" -v m="$min" 'BEGIN { exit !(s >= m) }'; then echo "seam $name SSIM $s"
  else echo "✗ seam $name SSIM ${s:-?}, want ≥ $min"; fail=1; fi
done <<'REGIONS'
whole 1920:1080:0:0 0.99
roamy 300:260:880:120 0.96
phone 480:980:1150:50 0.98
REGIONS
exit $fail
