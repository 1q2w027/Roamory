//
//  StudioSheet.swift
//  Roamory
//

import RoamoryKit
import SwiftUI

/// Make video: sends this trip's clips to a Mac running Roamory Studio, where Claude Code edits them with FFmpeg,
/// and saves the result to Photos.
struct StudioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var browser = StudioBrowser()
    @State private var clips = TripClips.all()
    @State private var selected: StudioMac?
    @State private var code = ""
    @State private var pairedHosts: Set<String> = []
    @State private var stage: String?
    @State private var startedAt: Date?
    /// When the Mac expects Claude to finish, from its latest estimate.
    @State private var finishesAt: Date?
    @State private var outcome: String?
    @State private var work: Task<Void, Never>?
    @State private var confirmDelete = false

    private var isWorking: Bool { work != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(clips.isEmpty ? "No clips saved yet" : "^[\(clips.count) clip](inflect: true) saved this trip")
                    if !clips.isEmpty && !isWorking {
                        Button("Delete trip clips", role: .destructive) { confirmDelete = true }
                    }
                } footer: {
                    Text("Clips stay in Photos too. Deleting them here starts a new trip.")
                }

                Section {
                    if browser.macs.isEmpty {
                        Label("Looking for Roamory Studio on this Wi-Fi…", systemImage: "wifi")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(browser.macs) { mac in
                        Button { selected = mac } label: {
                            HStack {
                                Label(mac.name, systemImage: "desktopcomputer")
                                Spacer()
                                if pairedHosts.contains(mac.host) { Text("Paired").foregroundStyle(.secondary) }
                                if selected == mac { Image(systemName: "checkmark") }
                            }
                        }
                        .disabled(isWorking)
                    }
                } header: {
                    Text("Mac")
                } footer: {
                    Text(browser.failure ?? "On the Mac, run python -m studio.server in the Roamory repo to start Roamory Studio.")
                }

                if let mac = selected, !pairedHosts.contains(mac.host) {
                    Section {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                        Button("Pair") { pair(mac) }
                            .disabled(code.count != 6 || isWorking)
                    } footer: {
                        Text("The code is shown in the Mac's terminal.")
                    }
                }

                Section {
                    if isWorking {
                        Button("Cancel", role: .destructive) { work?.cancel() }
                    } else {
                        Button("Make video") { makeVideo() }
                            .disabled(clips.isEmpty || selected.map { !pairedHosts.contains($0.host) } ?? true)
                    }
                    if let startedAt, let stage {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            let s = Int(context.date.timeIntervalSince(startedAt))
                            VStack(alignment: .leading, spacing: 4) {
                                Label("\(stage) · \(String(format: "%d:%02d", s / 60, s % 60))", systemImage: "wand.and.sparkles")
                                if let finishesAt {
                                    Label(Self.timeLeft(finishesAt.timeIntervalSince(context.date)), systemImage: "hourglass")
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let outcome { Text(outcome) }
                } footer: {
                    Text("Roamory Studio watches the clips, cuts them to your style and renders the video. This takes a few minutes; keep Roamory open.")
                }

                Section {
                    Button("Make on this iPhone") { makeOnPhone() }
                        .disabled(clips.isEmpty || isWorking)
                } header: {
                    Text("Without a Mac")
                } footer: {
                    Text("A simpler edit made on the iPhone: evenly spaced cuts from every clip in your style, with music and a title. Keep Roamory open.")
                }
            }
            .navigationTitle("Make video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(isWorking) }
            }
            .confirmationDialog("Delete this trip's clips?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete clips", role: .destructive) {
                    TripClips.deleteAll()
                    clips = []
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onAppear { browser.start() }
        .onDisappear {
            browser.stop()
            work?.cancel()
        }
        .onChange(of: browser.macs) {
            pairedHosts = Set(browser.macs.filter { $0.token.load() != nil }.map(\.host))
            if selected == nil || !browser.macs.contains(selected!) { selected = browser.macs.first }
        }
    }

    private func pair(_ mac: StudioMac) {
        outcome = nil
        work = Task {
            defer { work = nil }
            do {
                try await StudioClient.pair(mac, code: code)
                pairedHosts.insert(mac.host)
                code = ""
            } catch {
                outcome = error.localizedDescription
            }
        }
    }

    /// Moves the finished video to where the Gallery finds it, replacing an earlier video of this trip in this style.
    private func keepForGallery(_ video: URL, style: String) throws -> URL {
        let url = GalleryItem.videoURL(tripID: TripClips.tripID, style: style)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: url)
        try fm.moveItem(at: video, to: url)
        return url
    }

    private func makeVideo() {
        guard let mac = selected else { return }
        outcome = nil
        startedAt = .now
        stage = "Starting"
        let defaults = UserDefaults.standard
        let city = defaults.string(forKey: TripSettings.Key.city).flatMap { $0.isEmpty ? nil : $0 }
        let context: [String: Any] = [
            "destination": ["country": defaults.string(forKey: TripSettings.Key.country) ?? "Somewhere",
                            "city": city.map { $0 as Any } ?? NSNull()],
            "length_hours": TripSettings.lengthHours(defaults),
            "trip_type": defaults.string(forKey: TripSettings.Key.tripType) ?? "trip",
            "start_date": clips.first.map { $0.recordedAt.formatted(.iso8601.year().month().day()) } ?? "",
        ]
        let clips = clips
        work = Task {
            defer {
                work = nil
                startedAt = nil
                stage = nil
                finishesAt = nil
            }
            do {
                let style = TripSettings.style().rawValue
                let video = try await StudioClient.makeVideo(on: mac, clips: clips, style: style, context: context,
                                                             stage: { stage = $0 },
                                                             eta: { finishesAt = $0.map { Date.now + $0 } })
                // Kept in the app for the Gallery; if that fails, Photos still gets it and the download goes.
                let kept = try? keepForGallery(video, style: style)
                outcome = await PhotoLibrary.saveVideo(kept ?? video)
                if kept == nil { try? FileManager.default.removeItem(at: video) }
            } catch is CancellationError {
                outcome = "Cancelled"
            } catch {
                outcome = (error as? URLError)?.code == .cancelled ? "Cancelled" : error.localizedDescription
            }
        }
    }

    /// "About 6 min left", rounded up to the minute; "Finishing up" once the estimate has run out.
    private static func timeLeft(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "Finishing up" }
        if seconds < 60 { return "Under a minute left" }
        return "About \(Int((seconds / 60).rounded(.up))) min left"
    }

    /// The backup: renders with AVFoundation on the phone, no Mac needed.
    private func makeOnPhone() {
        outcome = nil
        startedAt = .now
        stage = "Rendering on iPhone"
        let clips = clips
        work = Task {
            defer {
                work = nil
                startedAt = nil
                stage = nil
            }
            do {
                let video = try await PhoneVideo.make(clips: clips, style: TripSettings.style()) { progress in
                    Task { @MainActor in
                        if stage != nil { stage = "Rendering on iPhone \(Int(progress * 100))%" }
                    }
                }
                outcome = await PhotoLibrary.saveVideo(video)
                try? FileManager.default.removeItem(at: video)
            } catch {
                outcome = Task.isCancelled ? "Cancelled" : error.localizedDescription
            }
        }
    }
}
