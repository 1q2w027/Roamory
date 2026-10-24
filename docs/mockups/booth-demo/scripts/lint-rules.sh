#!/usr/bin/env bash
# Project rules HyperFrames' own check doesn't cover. Run from anywhere; exits non-zero on a violation.
set -u
cd "$(dirname "$0")/.."
fail=0
src=(index.html compositions assets/beats.js)
# grep exits 2 when a path is missing, so judge by its output.
found() { local out; out=$(grep -rnsE "$@" "${src[@]}"); [ -n "$out" ] && echo "$out"; }

# Motion must come from the GSAP timeline, never a clock or a CSS animation.
if found '@keyframes|animation:|Math\.random|Date\.now|repeat: *-1|requestAnimationFrame|setTimeout|setInterval'; then
  echo "✗ clock-driven or CSS animation found (use the GSAP timeline)"; fail=1
fi
# Fonts resolve from HyperFrames' bundle (Nunito), never fetched by the page.
if found 'fonts\.(googleapis|gstatic)\.com'; then
  echo "✗ web font URL found (Nunito is bundled; use it by name)"; fail=1
fi
# The old orange mockup palette is out.
if found -i '#ff7a59|#ffb36b|#ff8a4c'; then
  echo "✗ orange palette from the old mockup"; fail=1
fi
# Every footage file is credited and small.
if [ -d assets/footage ]; then
  for f in assets/footage/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    grep -qF "$name" CREDITS.md 2>/dev/null || { echo "✗ $name is not in CREDITS.md"; fail=1; }
    [ "$(stat -f%z "$f")" -le 3145728 ] || { echo "✗ $name is over 3 MB"; fail=1; }
  done
fi
[ $fail -eq 0 ] && echo "✓ project rules"
exit $fail
