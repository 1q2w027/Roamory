// roamory-music: renders a score Claude writes (JSON) to a 48 kHz stereo WAV, so the edit's music is composed by the
// agent rather than taken from a file. Synthesised instruments, ADSR, filters, pan and a shared reverb.
// Usage: roamory-music <score.json>   (paths are relative to the job workspace; see studio/prompt.md for the format)
import Foundation

let rate = 48_000.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("roamory-music: \(message)\n".data(using: .utf8)!)
    exit(2)
}

func safePath(_ path: String) -> String {
    if path.hasPrefix("/") || path.split(separator: "/").contains("..") { fail("\(path): use a path inside the workspace") }
    return path
}

guard CommandLine.arguments.count == 2 else { fail("usage: roamory-music <score.json>") }
let scorePath = safePath(CommandLine.arguments[1])
guard let data = FileManager.default.contents(atPath: scorePath),
      let score = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { fail("\(scorePath) is not a JSON object") }

func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
func dB(_ d: Double) -> Double { pow(10, d / 20) }

// Pitch: MIDI number, or a name like "C4", "F#3", "Bb2" (C4 = 60).
func midi(_ v: Any) -> Double? {
    if let n = num(v) { return n }
    guard let s = v as? String, let letter = s.first?.uppercased() else { return nil }
    let base: [String: Double] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    guard var p = base[letter] else { return nil }
    var rest = s.dropFirst()
    while let c = rest.first, c == "#" || c == "b" { p += c == "#" ? 1 : -1; rest = rest.dropFirst() }
    guard let octave = Double(rest) else { return nil }
    return p + (octave + 1) * 12
}
func hz(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

// Deterministic noise.
var seed: UInt64 = 0x9E3779B97F4A7C15
func noise() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(Int64(bitPattern: seed)) / Double(Int64.max)
}

struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0, x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    init() {}
    init(_ kind: String, _ f: Double, q: Double = 0.707) { set(kind, f, q: q) }
    mutating func set(_ kind: String, _ f: Double, q: Double = 0.707) {
        let w = 2 * Double.pi * min(max(f, 20), rate * 0.45) / rate, alpha = sin(w) / (2 * q), c = cos(w)
        let a0 = 1 + alpha
        switch kind {
        case "highpass": (b0, b1, b2) = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
        case "bandpass": (b0, b1, b2) = (alpha, 0, -alpha)
        default: (b0, b1, b2) = ((1 - c) / 2, 1 - c, (1 - c) / 2)
        }
        (b0, b1, b2, a1, a2) = (b0 / a0, b1 / a0, b2 / a0, -2 * c / a0, (1 - alpha) / a0)
    }
    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        (x2, x1, y2, y1) = (x1, x, y1, y)
        return y
    }
}

// Instrument defaults: envelope (s), lowpass cutoff (Hz, 0 = none) and how a voice sounds.
struct Patch { var a: Double, d: Double, s: Double, r: Double, cutoff: Double }
let patches: [String: Patch] = [
    "sine": Patch(a: 0.01, d: 0.1, s: 0.8, r: 0.2, cutoff: 0),
    "triangle": Patch(a: 0.01, d: 0.1, s: 0.8, r: 0.2, cutoff: 0),
    "square": Patch(a: 0.01, d: 0.1, s: 0.7, r: 0.15, cutoff: 4000),
    "saw": Patch(a: 0.01, d: 0.1, s: 0.7, r: 0.15, cutoff: 5000),
    "pad": Patch(a: 0.8, d: 0.5, s: 0.8, r: 1.5, cutoff: 1800),
    "strings": Patch(a: 0.35, d: 0.3, s: 0.85, r: 0.8, cutoff: 3500),
    "choir": Patch(a: 0.5, d: 0.3, s: 0.9, r: 1.0, cutoff: 2200),
    "pluck": Patch(a: 0.001, d: 0, s: 1, r: 0.1, cutoff: 0),
    "piano": Patch(a: 0.002, d: 0, s: 1, r: 0.3, cutoff: 0),
    "epiano": Patch(a: 0.002, d: 0, s: 1, r: 0.3, cutoff: 0),
    "bell": Patch(a: 0.002, d: 0, s: 1, r: 0.5, cutoff: 0),
    "marimba": Patch(a: 0.001, d: 0, s: 1, r: 0.1, cutoff: 0),
    "organ": Patch(a: 0.02, d: 0.05, s: 0.9, r: 0.1, cutoff: 6000),
    "lead": Patch(a: 0.02, d: 0.2, s: 0.7, r: 0.2, cutoff: 3000),
    "bass": Patch(a: 0.005, d: 0.2, s: 0.6, r: 0.08, cutoff: 700),
    "sub": Patch(a: 0.005, d: 0.1, s: 0.9, r: 0.1, cutoff: 0),
    "kick": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "snare": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "clap": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "hat": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "open_hat": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "shaker": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "tom": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "crash": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
    "riser": Patch(a: 0, d: 0, s: 1, r: 0.2, cutoff: 0),
    "impact": Patch(a: 0, d: 0, s: 1, r: 0, cutoff: 0),
]
let percussive: Set = ["pluck", "piano", "epiano", "bell", "marimba", "kick", "snare", "clap", "hat", "open_hat",
                       "shaker", "tom", "crash", "impact"]
// Natural decay (s) of percussive instruments; the note's duration only cuts it short with a release.
let ring: [String: Double] = ["pluck": 1.5, "piano": 2.5, "epiano": 1.8, "bell": 3.5, "marimba": 0.6, "kick": 0.45,
                              "snare": 0.25, "clap": 0.3, "hat": 0.06, "open_hat": 0.4, "shaker": 0.08, "tom": 0.5,
                              "crash": 2.5, "impact": 3.0]

// One note of one instrument, mono. f is Hz, dur the held seconds.
func voice(_ inst: String, _ f: Double, _ dur: Double, _ p: Patch, detune: Double) -> [Double] {
    let isPerc = percussive.contains(inst)
    let held = isPerc ? min(dur, ring[inst] ?? 1) : dur
    let length = held + p.r + (isPerc ? 0.02 : 0)
    let n = max(1, Int(length * rate))
    var out = [Double](repeating: 0, count: n)
    var phases = [Double](repeating: 0, count: 8)
    var filter = p.cutoff > 0 ? Biquad("lowpass", p.cutoff) : Biquad()
    var hp = Biquad("highpass", inst == "hat" || inst == "shaker" ? 7000 : inst == "open_hat" ? 6000 : 3000)
    var bp = Biquad("bandpass", inst == "clap" ? 1200 : 2500, q: 0.8)
    // Karplus-Strong string for the pluck.
    let ksLen = max(2, Int(rate / f))
    var ks = (0..<ksLen).map { _ in noise() }
    var ksIdx = 0
    var riserLP = Biquad("lowpass", 200), rumble = Biquad("lowpass", 400)
    func osc(_ k: Int, _ freq: Double, _ shape: String) -> Double {
        phases[k] += freq / rate
        phases[k] -= floor(phases[k])
        let ph = phases[k]
        switch shape {
        case "saw": return 2 * ph - 1
        case "square": return ph < 0.5 ? 1 : -1
        case "triangle": return 4 * abs(ph - 0.5) - 1
        default: return sin(2 * .pi * ph)
        }
    }
    for i in 0..<n {
        let t = Double(i) / rate
        // Sustained envelope; percussive ones decay on their own.
        var env: Double
        if isPerc {
            env = t < held + 0.02 ? 1 : max(0, 1 - (t - held - 0.02) / max(p.r, 0.001))
        } else if t < p.a {
            env = t / p.a
        } else if t < p.a + p.d {
            env = 1 - (1 - p.s) * (t - p.a) / p.d
        } else if t < dur {
            env = p.s
        } else {
            env = p.s * max(0, 1 - (t - dur) / max(p.r, 0.001))
        }
        if !isPerc && t < dur && dur < p.a { env = min(env, t / p.a) }
        let vib = 1 + 0.004 * sin(2 * .pi * 5.5 * t) * min(1, t / 0.4)
        var x: Double
        switch inst {
        case "triangle", "square", "saw", "sine": x = osc(0, f * detune, inst)
        case "pad": x = (osc(0, f * 0.994, "saw") + osc(1, f * 1.006, "saw") + osc(2, f / 2, "triangle")) / 2.4
        case "strings": x = (osc(0, f * vib * 0.997, "saw") + osc(1, f * vib * 1.003, "saw") + osc(2, f * 2 * vib, "saw") * 0.3) / 2.3
        case "choir": x = (osc(0, f * vib, "triangle") + osc(1, f * 1.004 * vib, "triangle") + osc(2, f * 2, "sine") * 0.4 + osc(3, f * 3, "sine") * 0.2) / 2.6
        case "organ": x = (osc(0, f, "sine") + osc(1, f * 2, "sine") * 0.6 + osc(2, f * 3, "sine") * 0.4 + osc(3, f * 4, "sine") * 0.25 + osc(4, f / 2, "sine") * 0.5) / 2.75
        case "lead": x = (osc(0, f * vib, "square") * 0.6 + osc(1, f * vib * 1.005, "saw") * 0.5)
        case "bass": x = osc(0, f, "saw") * 0.7 + osc(1, f / 2, "square") * 0.3
        case "sub": x = osc(0, f, "sine") + osc(1, f * 2, "sine") * 0.15
        case "pluck":
            let next = (ksIdx + 1) % ksLen
            x = ks[ksIdx]
            ks[ksIdx] = 0.996 * 0.5 * (ks[ksIdx] + ks[next])
            ksIdx = next
        case "piano":
            x = 0
            for h in 1...6 {
                let hd = Double(h)
                x += osc(h, f * hd * (1 + 0.0004 * hd * hd), "sine") * exp(-t * (1.2 + hd * 0.9)) / hd
            }
            x *= 0.9 * min(1, t / 0.002)
        case "epiano":
            phases[1] += f / rate; phases[1] -= floor(phases[1])
            x = sin(2 * .pi * phases[1] + 1.6 * exp(-t * 6) * osc(0, f * 1.0, "sine")) * exp(-t * 1.6)
        case "bell":
            phases[1] += f / rate; phases[1] -= floor(phases[1])
            x = sin(2 * .pi * phases[1] + 2.5 * exp(-t * 2) * osc(0, f * 3.5, "sine")) * exp(-t * 1.1)
        case "marimba": x = (osc(0, f, "sine") + osc(1, f * 4, "sine") * 0.3 * exp(-t * 30)) * exp(-t * 8)
        case "kick": x = sin(2 * .pi * (45 * t + 105 * (1 - exp(-t * 25)) / 25)) * exp(-t * 7) + noise() * exp(-t * 300) * 0.2
        case "tom": x = sin(2 * .pi * (f * t + f * 0.8 * (1 - exp(-t * 12)) / 12)) * exp(-t * 7)
        case "snare": x = bp.run(noise()) * 1.6 * exp(-t * 18) + osc(0, 185, "sine") * 0.5 * exp(-t * 30)
        case "clap":
            let burst = [0, 0.011, 0.022].reduce(0) { $0 + (t >= $1 ? exp(-(t - $1) * 120) : 0) } + exp(-t * 14) * 0.4
            x = bp.run(noise()) * burst * 1.4
        case "hat": x = hp.run(noise()) * exp(-t * 70)
        case "open_hat": x = hp.run(noise()) * exp(-t * 9)
        case "shaker": x = hp.run(noise()) * sin(.pi * min(1, t / 0.07)) * 0.8
        case "crash": x = hp.run(noise()) * exp(-t * 1.6) * 0.8
        case "riser":
            riserLP.set("lowpass", 200 + 9000 * pow(min(1, t / max(dur, 0.01)), 2), q: 2)
            x = riserLP.run(noise()) * min(1, t / max(dur, 0.01)) + osc(0, f * pow(2, 2 * t / max(dur, 0.01)), "saw") * 0.15
        case "impact": x = sin(2 * .pi * (35 * t + 60 * (1 - exp(-t * 8)) / 8)) * exp(-t * 1.8) + rumble.run(noise()) * 2 * exp(-t * 4)
        default: x = osc(0, f, "sine")
        }
        if p.cutoff > 0 && !["pluck", "kick", "tom"].contains(inst) { x = filter.run(x) }
        out[i] = x * env
    }
    return out
}

// Freeverb-style stereo reverb.
struct Reverb {
    var combs: [[Double]], idx: [Int], store: [Double], aps: [[Double]], apIdx: [Int], feedback: Double, damp: Double
    init(size: Double, offset: Int) {
        let combLens = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map { Int(Double($0 + offset) * rate / 44_100) }
        let apLens = [556, 441, 341, 225].map { Int(Double($0 + offset) * rate / 44_100) }
        combs = combLens.map { [Double](repeating: 0, count: $0) }
        aps = apLens.map { [Double](repeating: 0, count: $0) }
        idx = combLens.map { _ in 0 }; apIdx = apLens.map { _ in 0 }; store = combLens.map { _ in 0 }
        feedback = 0.7 + 0.28 * min(max(size, 0), 1); damp = 0.25
    }
    mutating func run(_ x: Double) -> Double {
        var y = 0.0
        for k in 0..<combs.count {
            let out = combs[k][idx[k]]
            store[k] = out * (1 - damp) + store[k] * damp
            combs[k][idx[k]] = x * 0.015 + store[k] * feedback
            idx[k] = (idx[k] + 1) % combs[k].count
            y += out
        }
        for k in 0..<aps.count {
            let b = aps[k][apIdx[k]]
            aps[k][apIdx[k]] = y + b * 0.5
            apIdx[k] = (apIdx[k] + 1) % aps[k].count
            y = b - y
        }
        return y
    }
}

let bpm = num(score["bpm"]) ?? 100
let beat = 60 / bpm
let outPath = safePath(score["out"] as? String ?? "work/music.wav")
guard let tracks = score["tracks"] as? [[String: Any]], !tracks.isEmpty else { fail("score needs a non-empty tracks list") }

// Notes as (start s, midi, held s, velocity) per track, after loops and transposition.
struct Note { var t: Double, m: Double, d: Double, v: Double }
func parseNotes(_ track: [String: Any], _ name: String) -> [Note] {
    let transpose = (num(track["transpose"]) ?? 0) + 12 * (num(track["octave"]) ?? 0)
    let start = num(track["start"]) ?? 0
    let every = num(track["every"]) ?? 0
    let times = Int(num(track["repeat"]) ?? 1)
    var notes: [Note] = []
    for (k, raw) in (track["notes"] as? [Any] ?? []).enumerated() {
        // [beat, pitch or [pitches], beats, velocity] or {"t", "n", "d", "v"}.
        var t: Any?, n: Any?, d: Any?, v: Any?
        if let a = raw as? [Any] {
            (t, n, d, v) = (a.first, a.count > 1 ? a[1] : nil, a.count > 2 ? a[2] : nil, a.count > 3 ? a[3] : nil)
        } else if let o = raw as? [String: Any] {
            (t, n, d, v) = (o["t"], o["n"], o["d"], o["v"])
        }
        guard let tb = num(t) else { fail("\(name) note \(k): needs a start beat") }
        let pitches: [Any] = (n as? [Any]) ?? [n ?? 60]
        for p in pitches {
            guard let m = midi(p) ?? ((p as? String) == "x" ? 60 : nil) else { fail("\(name) note \(k): bad pitch \(p)") }
            notes.append(Note(t: (start + tb) * beat, m: m + transpose, d: (num(d) ?? 1) * beat, v: num(v) ?? 0.8))
        }
    }
    guard times > 1 else { return notes }
    guard every > 0 else { fail("\(name): repeat needs every (beats)") }
    return (0..<times).flatMap { r in notes.map { Note(t: $0.t + Double(r) * every * beat, m: $0.m, d: $0.d, v: $0.v) } }
}

let parsed = tracks.enumerated().map { (k, track) -> ([String: Any], String, [Note]) in
    let inst = track["instrument"] as? String ?? "sine"
    guard patches[inst] != nil else { fail("track \(k): unknown instrument \(inst); use one of \(patches.keys.sorted().joined(separator: ", "))") }
    return (track, inst, parseNotes(track, track["name"] as? String ?? "track \(k)"))
}
let lastEnd = parsed.flatMap { $0.2 }.map { $0.t + $0.d }.max() ?? 0
let total = num(score["length_s"]) ?? (lastEnd + 2.5)
let n = Int(total * rate)
var left = [Double](repeating: 0, count: n), right = left, sendL = left, sendR = left

for (track, inst, notes) in parsed {
    let base = patches[inst]!
    let patch = Patch(a: num(track["attack"]) ?? base.a, d: num(track["decay"]) ?? base.d,
                      s: num(track["sustain"]) ?? base.s, r: num(track["release"]) ?? base.r,
                      cutoff: num(track["cutoff"]) ?? base.cutoff)
    let gain = dB(num(track["gain_db"]) ?? -6)
    let pan = min(max(num(track["pan"]) ?? 0, -1), 1)
    let (gl, gr) = (cos((pan + 1) * .pi / 4), sin((pan + 1) * .pi / 4))
    let send = min(max(num(track["reverb"]) ?? 0.2, 0), 1)
    for (k, note) in notes.enumerated() {
        let samples = voice(inst, hz(note.m), note.d, patch, detune: 1 + 0.0015 * Double(k % 3 - 1))
        let s0 = Int(note.t * rate)
        for (i, x) in samples.enumerated() where s0 + i >= 0 && s0 + i < n {
            let y = x * gain * note.v
            left[s0 + i] += y * gl; right[s0 + i] += y * gr
            sendL[s0 + i] += y * gl * send; sendR[s0 + i] += y * gr * send
        }
    }
}

let room = score["reverb"] as? [String: Any] ?? [:]
var revL = Reverb(size: num(room["size"]) ?? 0.75, offset: 0), revR = Reverb(size: num(room["size"]) ?? 0.75, offset: 23)
let wet = num(room["mix"]) ?? 1
for i in 0..<n {
    left[i] += revL.run(sendL[i]) * wet
    right[i] += revR.run(sendR[i]) * wet
}

// Master: soft clip, normalise to master_db peak, 20 ms fade at both ends.
let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0, 1e-9)
let drive = 1 / peak
let target = dB(num(score["master_db"]) ?? -1) / tanh(1.2)
let fade = Int(0.02 * rate)
var pcm = Data(capacity: n * 4)
for i in 0..<n {
    let edge = min(1, Double(min(i, n - 1 - i)) / Double(fade))
    for x in [left[i], right[i]] {
        let y = tanh(x * drive * 1.2) * target * edge
        var s = Int16(max(-1, min(1, y)) * 32_767).littleEndian
        pcm.append(Data(bytes: &s, count: 2))
    }
}
func le<T: FixedWidthInteger>(_ v: T) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: MemoryLayout<T>.size) }
var wav = Data("RIFF".utf8) + le(UInt32(36 + pcm.count)) + Data("WAVEfmt ".utf8)
wav += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(rate)) + le(UInt32(rate * 4)) + le(UInt16(4)) + le(UInt16(16))
wav += Data("data".utf8) + le(UInt32(pcm.count)) + pcm
do { try wav.write(to: URL(fileURLWithPath: outPath)) } catch { fail("cannot write \(outPath): \(error.localizedDescription)") }
print(String(format: "%@: %.2f s at %g bpm (1 beat = %.3f s), %d tracks, %d notes", outPath, total, bpm, beat,
             parsed.count, parsed.reduce(0) { $0 + $1.2.count }))
