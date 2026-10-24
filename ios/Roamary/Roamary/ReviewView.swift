import AVKit
import RoamoryKit
import SwiftUI

/// The finished video: play it, jump to a moment (marked ones starred), save, share or try another style (TRD 10).
struct ReviewView: View {
    let pipeline: TripPipeline
    let url: URL
    var onDone: () -> Void

    @State private var player: AVPlayer
    @State private var saveMessage: String?
    @State private var saving = false

    init(pipeline: TripPipeline, url: URL, onDone: @escaping () -> Void) {
        self.pipeline = pipeline
        self.url = url
        self.onDone = onDone
        _player = State(initialValue: AVPlayer(url: url))
    }

    private var moments: [ReviewMoment] { pipeline.coordinator?.reviewMoments ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VideoPlayer(player: player)
                        .aspectRatio(aspect, contentMode: .fit)
                        .frame(maxHeight: 480)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(summary)
                }

                Section("Moments") {
                    ForEach(moments) { moment in
                        Button { play(from: moment.startS) } label: {
                            HStack {
                                Image(systemName: moment.isButton ? "star.fill" : "sparkles")
                                    .foregroundStyle(moment.isButton ? .yellow : .secondary)
                                Text(moment.description ?? (moment.isButton ? "Marked moment" : "Moment"))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(Self.time(moment.startS))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        saving = true
                        Task {
                            saveMessage = await PhotoLibrary.saveVideo(url)
                            saving = false
                        }
                    } label: {
                        Label(saveMessage ?? "Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(saving || saveMessage == "Saved to Photos")
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Menu {
                        ForEach(Style.allCases.filter { $0 != pipeline.trip.style }, id: \.self) { style in
                            Button(style.rawValue.capitalized) { Task { await pipeline.rerender(style: style) } }
                        }
                    } label: {
                        Label("Try another style", systemImage: "wand.and.stars")
                    }
                }
            }
            .navigationTitle(pipeline.trip.destination.city ?? pipeline.trip.destination.country)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
            .onAppear { player.play() }
            .onDisappear { player.pause() }
        }
    }

    private var aspect: CGFloat {
        guard let output = pipeline.coordinator?.renderResult?.spec.output, output.height > 0 else { return 9 / 16 }
        return CGFloat(output.width) / CGFloat(output.height)
    }

    private var summary: String {
        guard let c = pipeline.coordinator, let result = c.renderResult else { return "" }
        let plan = switch c.planOutcome?.source {
        case .cloud: "planned in the cloud"
        case .fallback, nil: "planned on the phone"
        }
        let short = c.planOutcome.map { EditSpecValidator.onlyTooShort($0.violations) } == true
            ? " Shorter than the style's target: not enough moments." : ""
        return String(format: "%@, %.0f s, %@.", pipeline.trip.style.rawValue.capitalized, result.durationS, plan) + short
    }

    private func play(from seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
