# Roamory tools

## Text: `roamory-text <spec.json>`

Homebrew's ffmpeg has no `drawtext`, so draw text with this tool and lay the PNGs over footage with `overlay`. Write a spec with the Write tool, then run it. `roamory-text --fonts` lists the installed font families.

```json
{"width": 1920, "height": 1080,
 "images": [
  {"out": "work/txt_title.png", "layers": [
    {"text": "KYOTO", "font": "Didot", "weight": "bold", "size": 0.16, "tracking": 0.3, "x": 0.5, "y": 0.45,
     "color": "#FFFFFF", "shadow": {"color": "#00000099", "blur": 0.02}},
    {"w": 0.3, "h": 0.004, "x": 0.5, "y": 0.58, "color": "#FFFFFFCC"},
    {"text": "City break · October 2026", "font": "Avenir Next", "weight": "medium", "italic": true, "size": 0.035,
     "x": 0.5, "y": 0.64, "color": "#F2C14E"}]},
  {"out": "work/txt_day1.png", "layers": [
    {"text": "Day 1", "font": "rounded", "weight": "heavy", "size": 0.06, "x": 0.06, "y": 0.9, "anchor": "bottom_left",
     "box": {"color": "#E4572ECC", "radius": 0.012, "padding": 0.3}, "rotation": -3}]}]}
```

- Top-level keys are defaults for every image in `images` (or give one image's keys at the top level). Images are transparent unless `background` is set (`"#000000"` for a card). Make them the output size unless you want a smaller sprite to move or scale.
- Text layers: `text` (`\n` for new lines), `font` (a family such as Futura, Avenir Next, Helvetica Neue, Didot, Bodoni 72, Baskerville, Georgia, Gill Sans, Copperplate, DIN Condensed, Impact, Marker Felt, Chalkboard SE, Bradley Hand, Snell Roundhand, American Typewriter; or `system`, `rounded`, `serif`, `mono`), `weight` (ultralight, thin, light, regular, medium, semibold, bold, heavy, black), `italic`, `size` (fraction of the short side), `color` (`#RRGGBB` or `#RRGGBBAA`), `tracking` (fraction of the size), `line_spacing`, `align` (left, center, right), `uppercase`, `max_width` (fraction of the width, shrinks to fit; default 0.9), `stroke` (`color`, `width` in % of the size), `shadow` (`color`, `blur`, `dx`, `dy`), `box` (`color`, `padding`, `radius`).
- Shape layers (no `text`): `w`, `h` (fractions of width and height), `color` (fill), `stroke` (`color`, `width`), `radius`, `"shape": "ellipse"`. Use them for rules, bars, frames, lower-third plates.
- Every layer: `x`, `y` (fractions from the top left), `anchor` for text (center, left, right, top, bottom, top_left, top_right, bottom_left, bottom_right), `rotation` (degrees, clockwise), `opacity`.

Animate in ffmpeg: input the PNG with `-loop 1 -t <s> -i work/txt.png`, then for example
- fade: `[1]format=rgba,fade=t=in:st=0.5:d=0.4:alpha=1,fade=t=out:st=3:d=0.4:alpha=1[t];[0][t]overlay=0:0`
- slide in with ease-out: `overlay=x='-200*pow(1-min(1,max(0,(t-0.5)/0.6)),3)':y=0`
- pop / grow: `[1]format=rgba,scale=w='iw*(0.7+0.3*min(1,t/0.25))':h=-1:eval=frame[t];[0][t]overlay=x='(W-w)/2':y='(H-h)/2':eval=frame`
- show only in a window: `overlay=...:enable='between(t,1,3.5)'`
- word by word or typewriter: one PNG per step, each overlaid in its own `enable` window.

## Music: `roamory-music <score.json>`

Compose an original score and render it to a 48 kHz stereo WAV. Write the score with the Write tool, run the tool, and listen with your eyes: `ffmpeg -i work/music.wav -lavfi showspectrumpic=s=1200x300:legend=0 frames/music.png` and read it, or check levels with `astats`.

```json
{"out": "work/music.wav", "bpm": 92, "length_s": 50.0, "master_db": -1, "reverb": {"size": 0.8},
 "tracks": [
  {"name": "chords", "instrument": "pad", "gain_db": -10, "reverb": 0.5, "every": 16, "repeat": 4,
   "notes": [[0, ["A3", "C4", "E4"], 4], [4, ["F3", "A3", "C4"], 4], [8, ["C3", "E3", "G3"], 4], [12, ["G3", "B3", "D4"], 4]]},
  {"name": "bass", "instrument": "bass", "gain_db": -8, "start": 16, "every": 4, "repeat": 12,
   "notes": [[0, "A1", 1], [1.5, "A1", 0.5], [2, "E2", 1], [3, "G1", 1]]},
  {"name": "kick", "instrument": "kick", "gain_db": -5, "reverb": 0, "start": 32, "every": 1, "repeat": 32, "notes": [[0, "x"]]},
  {"name": "motif", "instrument": "bell", "gain_db": -14, "pan": -0.3, "reverb": 0.6, "start": 8,
   "notes": [[0, "E5", 1, 0.7], [1, "A5", 1], [2, "C6", 2, 0.9], [4, "B5", 3]]},
  {"name": "lift", "instrument": "riser", "gain_db": -12, "start": 28, "notes": [[0, "C3", 4]]},
  {"name": "hit", "instrument": "impact", "gain_db": -8, "start": 32, "notes": [[0, "x", 2]]}]}
```

- Times are in beats (`60 / bpm` seconds each). A note is `[beat, pitch, beats, velocity]` (or `{"t", "n", "d", "v"}`); pitch is a name (`"C4"`, `"F#3"`, `"Bb2"`), a MIDI number, a list for a chord, or `"x"` for drums. Beats default to 1, velocity to 0.8.
- Track keys: `instrument`, `gain_db` (default -6), `pan` (-1 to 1), `reverb` (send, 0 to 1, default 0.2), `start` (beat offset), `every` + `repeat` (loop the notes every N beats), `transpose`, `octave`, `attack`, `decay`, `sustain`, `release` (s), `cutoff` (low-pass Hz).
- Instruments: tonal `pad`, `strings`, `choir`, `organ`, `piano`, `epiano`, `pluck`, `bell`, `marimba`, `lead`, `bass`, `sub`, `sine`, `triangle`, `square`, `saw`; drums `kick`, `snare`, `clap`, `hat`, `open_hat`, `shaker`, `tom`, `crash`; effects `riser` (noise sweep over the note's length), `impact`.
- The output is normalised to `master_db` peak; balance tracks with `gain_db`. Set `length_s` to the video's planned length.
- Write real music: a key and chord progression, a motif, sections that follow the edit (a sparse intro under the title, a build, a peak at the best shot, a resolution under the end card), and an ending on the last bar rather than a cut-off. Choose the bpm so cuts can land on beats.

