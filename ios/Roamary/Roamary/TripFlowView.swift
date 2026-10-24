import RoamoryKit
import SwiftUI

/// After a recording: Processing (finding moments, planning, rendering) until the video is ready, then Review.
struct TripFlowView: View {
    let pipeline: TripPipeline
    var onDone: () -> Void

    var body: some View {
        Group {
            if pipeline.coordinator?.phase == .completed, let url = pipeline.coordinator?.renderResult?.url {
                ReviewView(pipeline: pipeline, url: url, onDone: onDone)
                    .id(url)
            } else {
                ProcessingView(pipeline: pipeline, onClose: onDone)
            }
        }
        // Finding moments and rendering both need the app in the foreground (TRD 9.2).
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

struct ProcessingView: View {
    let pipeline: TripPipeline
    var onClose: () -> Void

    private enum Status {
        case working(step: String, progress: Double?)
        case failed(String)
    }

    private var status: Status {
        switch pipeline.phase {
        case .idle: return .working(step: "Starting", progress: nil)
        case let .finding(progress): return .working(step: "Finding your moments", progress: progress)
        case let .failed(message): return .failed(message)
        case .editing:
            switch pipeline.coordinator?.phase ?? .idle {
            case .idle: return .working(step: "Starting", progress: nil)
            case let .planning(step): return .working(step: step, progress: nil)
            case let .rendering(progress): return .working(step: "Making your video", progress: progress)
            case .completed: return .working(step: "Video ready", progress: 1)
            case let .error(stage, message):
                return .failed(stage == .noMoments ? "\(message) Mark moments with the star or a volume key next time." : message)
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch status {
            case let .working(step, progress):
                if let progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                } else {
                    ProgressView()
                }
                Text(step)
                    .font(.headline)
                Text("Keep Roamary open. This takes a minute or two.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text(message)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                    Button("Retry") { Task { await pipeline.retry() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .tint(.yellow)
        .animation(.default, value: pipeline.phase)
    }
}
