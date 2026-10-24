//
//  StudioClient.swift
//  Roamory
//

import Foundation
import Network
import Observation

/// A Mac running Roamory Studio (`studio/` in the repo) on this Wi-Fi.
struct StudioMac: Hashable, Identifiable {
    let name: String
    /// Its `.local` name, from the Bonjour TXT record.
    let host: String
    let port: Int

    var id: String { host }
    var baseURL: URL { URL(string: "http://\(host):\(port)")! }
    /// The token from pairing, in the Keychain.
    var token: KeychainItem { KeychainItem(service: "roamory.studio", account: host) }
}

/// Finds Roamory Studio Macs on the local network (`_roamory._tcp`).
@Observable
final class StudioBrowser {
    private(set) var macs: [StudioMac] = []
    private(set) var failure: String?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_roamory._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results.compactMap { result -> StudioMac? in
                guard case .service(let name, _, _, _) = result.endpoint,
                      case .bonjour(let txt) = result.metadata,
                      let host = txt["host"], let port = txt["port"].flatMap(Int.init) else { return nil }
                return StudioMac(name: name.replacingOccurrences(of: "Roamory Studio on ", with: ""), host: host, port: port)
            }
            Task { @MainActor [weak self] in self?.macs = macs.sorted { $0.name < $1.name } }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let failure: String? = switch state {
            case .failed(let error), .waiting(let error):
                "Can't search the local network (\(error.localizedDescription)). Allow Local Network for Roamory in Settings > Privacy & Security."
            default: nil
            }
            Task { @MainActor [weak self] in self?.failure = failure }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// Talks to a Roamory Studio Mac (contracts README, "/v1/studio"): pairs, uploads the trip's clips, waits while
/// Claude Code edits them, and downloads the video.
enum StudioClient {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private struct Job: Decodable {
        let status: String
        let stage: String?
        let error: ErrorBody?
    }

    private struct ErrorBody: Decodable {
        let message: String
    }

    /// Exchanges the code shown on the Mac for a token and keeps it in the Keychain.
    static func pair(_ mac: StudioMac, code: String) async throws {
        struct Paired: Decodable { let token: String }
        let data = try await send("POST", mac.baseURL.appending(path: "v1/studio/pair"), json: ["code": code])
        let token = try JSONDecoder().decode(Paired.self, from: data).token
        mac.token.save(token)
    }

    /// Sends `clips` to `mac`, reports Claude's progress through `stage`, and returns the finished video, a file
    /// the caller owns.
    static func makeVideo(on mac: StudioMac, clips: [TripClip], style: String, context: [String: Any],
                          stage: @escaping @MainActor (String) -> Void) async throws -> URL {
        guard let token = mac.token.load() else { throw Failure(errorDescription: "Pair with \(mac.name) first.") }
        let api = mac.baseURL.appending(path: "v1/studio/jobs")

        stage("Reading clips")
        let iso = ISO8601DateFormatter()
        var clipTable: [[String: Any]] = []
        for clip in clips {
            let (duration, hasAudio) = try await TripClips.details(of: clip)
            clipTable.append(["clip_id": clip.id, "recorded_at": iso.string(from: clip.recordedAt),
                              "duration_s": duration, "has_audio": hasAudio])
        }
        let request: [String: Any] = ["trip_id": TripClips.tripID, "style": style, "context": context, "clips": clipTable]
        struct Created: Decodable { let job_id: String }
        let jobID = try JSONDecoder().decode(Created.self, from: try await send("POST", api, json: request, token: token)).job_id
        let job = api.appending(path: jobID)

        do {
            for (k, clip) in clips.enumerated() {
                stage("Sending clip \(k + 1) of \(clips.count)")
                var upload = URLRequest(url: job.appending(path: "clips/\(clip.id).mp4"), timeoutInterval: 600)
                upload.httpMethod = "PUT"
                upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                upload.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await URLSession.shared.upload(for: upload, fromFile: clip.url)
                try check(data, response)
            }
            _ = try await send("POST", job.appending(path: "start"), token: token)

            while true {
                try await Task.sleep(for: .seconds(2))
                let state = try JSONDecoder().decode(Job.self, from: try await send("GET", job, token: token))
                if let line = state.stage { stage(line) }
                if state.status == "failed" {
                    throw Failure(errorDescription: state.error?.message ?? "Claude could not make the video.")
                }
                if state.status == "completed" { break }
            }

            stage("Downloading the video")
            var download = URLRequest(url: job.appending(path: "video"), timeoutInterval: 300)
            download.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (file, response) = try await URLSession.shared.download(for: download)
            try check(Data(), response)
            let video = FileManager.default.temporaryDirectory.appendingPathComponent("roamory-\(jobID).mp4")
            try? FileManager.default.removeItem(at: video)
            try FileManager.default.moveItem(at: file, to: video)
            return video
        } catch {
            // Free the Mac for the next try; the download already deleted a finished job.
            var cancel = URLRequest(url: job)
            cancel.httpMethod = "DELETE"
            cancel.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: cancel)
            throw error
        }
    }

    @discardableResult
    private static func send(_ method: String, _ url: URL, json: Any? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data, response)
        return data
    }

    private static func check(_ data: Data, _ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw Failure(errorDescription: status == 401 && message == nil ? "Pair with the Mac again."
                          : message ?? "The Mac returned an unexpected response (\(status)).")
        }
    }
}
