// detector-replay: run a recorded walk through Stage 1 detection on the Mac (TRD 12.1 gate 6, 12.4).
//
//   swift run detector-replay WALK.mp4 --labels labels.json [--server URL --token TOKEN]
//       [--style cinematic] [--trip-type honeymoon] [--country Japan] [--city Kyoto] [--demo]
//
// labels.json: {"should_save_ms": [...], "tolerance_ms": 10000}. Without --server, it reports what the gate
// escalates (no cloud; moments settle by the local fallback). With --server, each request finishes before the
// next sample, so start the backend with the trip budget raised (see backend/tools/replay_eval.py).
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

let options = parseOptions()
let config = try DetectionConfig.bundled()
let labels = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: options.labels))
let holder = CollectingHolder { event in
    switch event {
    case .hold(let h):
        print(String(format: "%7.1fs  hold %@ (%@)", Double(h.triggerMs) / 1000, h.momentId, h.source.rawValue))
    case .release(let id):
        print("          release \(id) (cloud said skip)")
    }
}
let evaluator: Evaluating? = options.server.map {
    EvaluateClient(baseURL: $0, token: options.token, timeoutS: config.evaluateTimeoutS)
}
let trip = TripInfo(
    tripId: "t_replay_\(UUID().uuidString.prefix(8).lowercased())", installId: "i_replay", style: options.style,
    tripType: options.tripType, destination: .init(continent: nil, country: options.country, city: options.city), lengthDays: 1
)
let detector = MomentDetector(trip: trip, config: config, holder: holder, evaluator: evaluator,
                              cloudAllowed: evaluator != nil, demoMode: options.demo, momentIdPrefix: "m")

let samples: Int
do {
    samples = try await FileDetection.detect(video: options.video, detector: detector, config: config,
                                             waitForRequests: evaluator != nil).count
} catch {
    FileHandle.standardError.write(Data("\(options.video.path): \(error)\n".utf8))
    exit(1)
}

var escalatedMs: [Int] = []
var keptMs: [Int] = []
print("\nmoment  trigger  decision")
for h in await holder.holds {
    escalatedMs.append(h.triggerMs)
    let decision = await detector.finalDecision(for: h.momentId)
    switch decision {
    case .keep(let source, _, let description, let score):
        keptMs.append(h.triggerMs)
        print(String(format: "%@  %6.1fs  KEEP (%@) %@ %@", h.momentId, Double(h.triggerMs) / 1000, source.rawValue,
                     score.map { String(format: "%.2f", $0) } ?? "-", description ?? ""))
    case .release:
        print(String(format: "%@  %6.1fs  release", h.momentId, Double(h.triggerMs) / 1000))
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
