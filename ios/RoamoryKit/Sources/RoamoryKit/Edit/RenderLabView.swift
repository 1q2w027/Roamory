#if DEBUG
import AVKit
import SwiftUI

/// Debug-only harness (TRD 12.2 render matrix): renders sample clips, or any .mp4 in the app's Documents
/// folder, through the real pipeline and logs render times. Until the trip state machine exists it is also
/// what drives `EditCoordinator`.
public struct RenderLabView: View {
    private struct Run: Identifiable {
        let id = UUID()
        var style: Style
        var clipCount: Int
        var summary: String
        var url: URL?
        var moments: [ReviewMoment]
    }

    @State private var clipCount = 3
    @State private var useCloud = false
    @State private var forceExportFailure = false
    @State private var current: EditCoordinator?
    @State private var runs: [Run] = []
    @State private var playing: URL?
    @State private var setupError: String?

    private let sources = RenderLab.sourceFiles()
    private let cloud = (try? EditConfig.bundled()).flatMap { PlanClient.fromBundle(config: $0) }

    public init() {}

    public var body: some View {
        Form {
            Section("Input") {
                Text("\(sources.count) source files (\(sources.first?.deletingLastPathComponent().lastPathComponent ?? "none"))")
                Picker("Clips", selection: $clipCount) {
                    ForEach([1, 3, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Cloud planner", isOn: $useCloud).disabled(cloud == nil)
                Toggle("Force export failure (hard-cut retry)", isOn: $forceExportFailure)
            }

            Section("Render") {
                ForEach(Style.allCases, id: \.self) { style in
                    Button("Render \(style.rawValue)") { Task { await render([style]) } }
                }
                Button("Render all four") { Task { await render(Style.allCases) } }
            }
            .disabled(current?.isRunning == true || sources.isEmpty)

            if let current {
                Section("Status") { Text(Self.describe(current.phase)) }
            }
            if let setupError {
                Section("Error") { Text(setupError).foregroundStyle(.red) }
            }

            Section("Results") {
                ForEach(runs.reversed()) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(run.style.rawValue), \(run.clipCount) clips").font(.headline)
                        Text(run.summary).font(.caption)
                        Text(run.moments.map { "\($0.isButton ? "●" : "○") \($0.momentId) @\(String(format: "%.1f", $0.startS))s" }
                            .joined(separator: "  ")).font(.caption2)
                        if let url = run.url {
                            HStack {
                                Button("Play") { playing = url }
                                ShareLink(item: url)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Render Lab")
        .sheet(item: Binding(get: { playing.map(PlayingURL.init) }, set: { playing = $0?.url })) { item in
            VideoPlayer(player: AVPlayer(url: item.url))
                .frame(minWidth: 320, minHeight: 320)
        }
    }

    private struct PlayingURL: Identifiable {
        var url: URL
        var id: URL { url }
    }

    private func render(_ styles: [Style]) async {
        setupError = nil
        do {
            let presets = try StylePresets.bundled()
            let config = try EditConfig.bundled()
            let clips = try await RenderLab.clips(count: clipCount, from: sources)
            var renderer = Renderer(config: config)
            renderer.simulateTransitionFailure = forceExportFailure
            let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "RenderLab")
            for style in styles {
                var trip = RenderLab.trip
                trip.style = style
                trip.allowCloudAnalysis = useCloud
                let coordinator = EditCoordinator(
                    trip: trip, clips: clips, outputDirectory: output, presets: presets, config: config,
                    service: useCloud ? cloud : nil, renderer: renderer
                )
                current = coordinator
                await coordinator.run()
                runs.append(Run(style: style, clipCount: clipCount, summary: Self.summary(coordinator),
                                url: coordinator.renderResult?.url, moments: coordinator.reviewMoments))
            }
        } catch {
            setupError = String(describing: error)
        }
    }

    private static func summary(_ c: EditCoordinator) -> String {
        guard let result = c.renderResult else { return describe(c.phase) }
        let source = switch c.planOutcome?.source {
        case .cloud: "cloud plan"
        case let .fallback(reason): "fallback (\(reason))"
        case nil: "?"
        }
        let short = c.planOutcome.map { EditSpecValidator.onlyTooShort($0.violations) } == true ? ", short: not enough footage" : ""
        return String(format: "%.1f s video in %.1f s, ", result.durationS, result.elapsedS) + source
            + (result.usedHardCutRetry ? ", hard-cut retry" : "") + short
    }

    private static func describe(_ phase: EditCoordinator.Phase) -> String {
        switch phase {
        case .idle: "Idle"
        case let .planning(step): "Planning: \(step)"
        case let .rendering(progress): "Rendering \(Int(progress * 100))%"
        case .completed: "Video ready"
        case let .error(stage, message): "Error (\(stage.rawValue)): \(message)"
        }
    }
}
#endif
