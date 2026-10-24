#!/usr/bin/env bash
# Regenerates the placeholder media bundled in Sources/RoamoryKit/Resources:
# the 2 s black end-card clips, one music bed per preset, and the RenderLab sample clips.
# Placeholders until music licensing is settled (TRD 9.2). Needs ffmpeg with libx264.
set -euo pipefail
cd "$(dirname "$0")/../Sources/RoamoryKit/Resources"
mkdir -p Music SampleClips
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
x264=(-c:v libx264 -pix_fmt yuv420p -preset veryfast -movflags +faststart)

# End-card backgrounds: small, the renderer scales them to the output size.
ff -f lavfi -i color=black:s=320x180:r=30 -t 2 "${x264[@]}" black_16x9.mp4
ff -f lavfi -i color=black:s=180x320:r=30 -t 2 "${x264[@]}" black_9x16.mp4

# Music beds: 16 s loops (a whole number of beats and pad cycles), the renderer loops them.
music() { ff -f lavfi -i "aevalsrc='$2':s=44100:d=16" -ac 2 -c:a aac -b:a 96k "Music/$1.m4a"; }
music cinematic_01 "0.12*(sin(2*PI*110*t)+sin(2*PI*130.81*t)+sin(2*PI*164.81*t)+0.5*sin(2*PI*220*t))*(0.6+0.4*sin(2*PI*t/8))"
music reels_01 "0.5*sin(2*PI*55*t)*exp(-14*mod(t,0.5))+0.12*(sin(2*PI*220*t)+sin(2*PI*277.18*t)+sin(2*PI*329.63*t))*exp(-5*mod(t+0.25,0.5))"
music documentary_01 "0.18*(sin(2*PI*73.42*t)+0.7*sin(2*PI*110*t)+0.3*sin(2*PI*146.83*t))*(0.75+0.25*sin(2*PI*t/16))"
music vlog_01 "0.25*sin(2*PI*t*(261.63*eq(floor(mod(4*t,4)),0)+329.63*eq(floor(mod(4*t,4)),1)+392*eq(floor(mod(4*t,4)),2)+523.25*eq(floor(mod(4*t,4)),3)))*exp(-6*mod(t,0.25))"

# Sample clips for RenderLab: landscape, landscape with audio, rotated (like iPhone footage
# with a preferredTransform) and native portrait.
clip() { ff -f lavfi -i "testsrc2=s=$2:r=30,hue=h=$3" -t 12 "${@:4}" "${x264[@]}" -crf 34 "SampleClips/$1.mp4"; }
clip sample_a 640x360 0
clip sample_b 640x360 120 -f lavfi -i "sine=f=330:d=12" -c:a aac -b:a 64k -shortest
clip rot_tmp 640x360 240
ff -display_rotation 90 -i SampleClips/rot_tmp.mp4 -c copy SampleClips/sample_c.mp4 && rm SampleClips/rot_tmp.mp4
clip sample_d 360x640 60
ls -la . Music SampleClips
