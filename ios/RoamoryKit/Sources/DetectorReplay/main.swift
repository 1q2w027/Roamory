// detector-replay: run a recorded walk through Stage 1 detection on the Mac (TRD 12.1 gate 6, 12.4).
//
//   swift run detector-replay WALK.mp4 --labels labels.json [--server URL --token TOKEN]
//       [--style cinematic] [--trip-type honeymoon] [--country Japan] [--city Kyoto] [--demo]
//
// labels.json: {"should_save_ms": [...], "tolerance_ms": 10000}. Without --server, it reports what the gate
// escalates (no cloud; moments settle by the local fallback). With --server, each request finishes before the
// next sample, so start the backend with the trip budget raised (see backend/tools/replay_eval.py).
import AVFoundation
import Foundation
import RoamoryKit

struct Options {
    var video: URL
    var labels: URL
    var server: URL?
    var token = ""
    var style: Style = .cinematic
    var tripType = "honeymoon"
    var country = "Japan"
    var city = "Kyoto"
    var demo = false
}

func parseOptions() -> Options {
    var args = Array(CommandLine.arguments.dropFirst())
    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\nusage: detector-replay WALK.mp4 --labels labels.json [--server URL --token TOKEN] [--style S] [--trip-type T] [--country C] [--city C] [--demo]\n".utf8))
        exit(2)
    }
    guard let first = args.first, !first.hasPrefix("--") else { fail("missing video path") }
    args.removeFirst()
    var labels: URL?
    var o = Options(video: URL(fileURLWithPath: first), labels: URL(fileURLWithPath: "/dev/null"))
    while !args.isEmpty {
        let flag = args.removeFirst()
        if flag == "--demo" { o.demo = true; continue }
        guard !args.isEmpty else { fail("\(flag) needs a value") }
        let value = args.removeFirst()
        switch flag {
        case "--labels": labels = URL(fileURLWithPath: value)
        case "--server": o.server = URL(string: value)
        case "--token": o.token = value
        case "--style": o.style = Style(rawValue: value) ?? { fail("unknown style \(value)") }()
        case "--trip-type": o.tripType = value
        case "--country": o.country = value
        case "--city": o.city = value
        default: fail("unknown flag \(flag)")
        }
    }
    guard let labels else { fail("--labels is required") }
    o.labels = labels
    return o
}

struct Labels: Decodable {
    var shouldSaveMs: [Int]
    var toleranceMs: Int?

    enum CodingKeys: String, CodingKey {
        case shouldSaveMs = "should_save_ms"
        case toleranceMs = "tolerance_ms"
    }
}

/// Stands in for the rolling buffer: remembers each hold and release.
actor LoggingHolder: MomentHolder {
    var holds: [(id: String, triggerMs: Int, source: MomentSource)] = []
    var released: Set<String> = []

    func hold(triggerMs: Int, source: MomentSource) -> String {
        let id = "m_\(holds.count + 1)"
        holds.append((id, triggerMs, source))
        print(String(format: "%7.1fs  hold %@ (%@)", Double(triggerMs) / 1000, id, source.rawValue))
        return id
    }

    func release(_ momentId: String) {
        released.insert(momentId)
        print("          release \(momentId) (cloud said skip)")
    }
}

let options = parseOptions()
let config = try DetectionConfig.bundled()
let labels = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: options.labels))
let holder = LoggingHolder()
let evaluator: Evaluating? = options.server.map {
    EvaluateClient(baseURL: $0, token: options.token, timeoutS: config.evaluateTimeoutS)
}
let trip = TripInfo(
    tripId: "t_replay_\(UUID().uuidString.prefix(8).lowercased())", installId: "i_replay", style: options.style,
    tripType: options.tripType, destination: .init(continent: nil, country: options.country, city: options.city), lengthDays: 1
)
let detector = MomentDetector(trip: trip, config: config, holder: holder, evaluator: evaluator,
                              cloudAllowed: evaluator != nil, demoMode: options.demo)

let asset = AVURLAsset(url: options.video)
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    FileHandle.standardError.write(Data("no video track in \(options.video.path)\n".utf8))
    exit(1)
}
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
reader.startReading()

let intervalMs = Int(config.sampleIntervalS * 1000)
var nextMarkMs = 0
var samples = 0
var latencies: [Int] = []
while let sample = output.copyNextSampleBuffer() {
    let tMs = Int(CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1000)
    guard tMs >= nextMarkMs, let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    nextMarkMs += intervalMs * ((tMs - nextMarkMs) / intervalMs + 1)
    guard let jpeg = FrameSampler.jpeg(pixels, longEdge: config.jpegLongEdgePx, quality: config.jpegQuality) else { continue }
    let luma = FrameSampler.luma(pixels, width: config.lumaWidth, height: config.lumaHeight)
    samples += 1
    await detector.ingest(SampledFrame(tMs: tMs, luma: luma, jpeg: jpeg, dwell: 0))
    if evaluator != nil { await detector.waitForIdle() }
}
if reader.status == .failed { print("reader failed: \(reader.error?.localizedDescription ?? "unknown")") }
await detector.waitForIdle()

var escalatedMs: [Int] = []
var keptMs: [Int] = []
print("\nmoment  trigger  decision")
for h in await holder.holds {
    escalatedMs.append(h.triggerMs)
    let decision = await detector.finalDecision(for: h.id)
    switch decision {
    case .keep(let source, _, let description, let score):
        keptMs.append(h.triggerMs)
        print(String(format: "%@  %6.1fs  KEEP (%@) %@ %@", h.id, Double(h.triggerMs) / 1000, source.rawValue,
                     score.map { String(format: "%.2f", $0) } ?? "-", description ?? ""))
    case .release:
        print(String(format: "%@  %6.1fs  release", h.id, Double(h.triggerMs) / 1000))
    }
}

let report = ReplayReport.compute(samples: samples, escalatedMs: escalatedMs, keptMs: keptMs,
                                  labelsMs: labels.shouldSaveMs, toleranceMs: labels.toleranceMs ?? 10_000)
print(String(format: "\nsamples %d  escalations %d  rate %.1f%% (gate 6: <= 10%%)",
             report.samples, report.escalations, report.escalationRate * 100))
for m in report.moments {
    print(String(format: "label %6.1fs  escalated %@  kept %@", Double(m.labelMs) / 1000,
                 m.escalated ? "yes" : "NO", m.kept ? "yes" : "NO"))
}
