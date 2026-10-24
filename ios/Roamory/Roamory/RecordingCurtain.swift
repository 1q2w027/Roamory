import SwiftUI
import UIKit

/// Recording mode (PRD FR-007, mockup screen 4): a black screen at 0% brightness over the camera UI.
/// Hold to wake it; it goes dark again after 10 s without a touch.
struct RecordingCurtain: View {
    /// While a clip is being saved: when it started, for the elapsed time.
    let savingStart: Date?
    @Binding var awake: Bool
    /// When the camera UI under the curtain was last touched; restarts the 10 s countdown.
    let lastTouch: Date
    /// A sheet is open over the camera: stay lit and do not count down.
    var paused = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var savedBrightness: CGFloat?
    @State private var holdProgress: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 150, height: 150)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.recording)
                            .frame(width: 10, height: 10)
                            .opacity(pulse ? 0.25 : 1)
                        Text("Recording")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.recording)
                    }
                }
                VStack(spacing: 4) {
                    Text("Screen at 0% brightness")
                    Text("Tap and hold to wake")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                pill("Capturing · 30 fps", color: Theme.recording)
                if let start = savingStart {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        let s = Int(context.date.timeIntervalSince(start))
                        pill(String(format: "Saving · %02d:%02d", s / 60, s % 60), color: Theme.accent)
                    }
                } else {
                    pill("Not saving", color: .white.opacity(0.35))
                }
                Spacer()
                Text("Shutter remote, volume key or AirPods: press to start or stop saving")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
            }
        }
        .opacity(awake ? 0 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            holdProgress = 0
            withAnimation(.easeOut(duration: 0.35)) { awake = true }
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 0.6) : .easeOut(duration: 0.2)) { holdProgress = pressing ? 1 : 0 }
        }
        // Outside the content shape and gesture, or they would still take touches meant for the camera UI.
        .allowsHitTesting(!awake)
        .sensoryFeedback(.impact(weight: .light), trigger: awake)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            updateBrightness()
        }
        .onDisappear(perform: restoreBrightness)
        .onChange(of: awake) { updateBrightness() }
        .onChange(of: paused) { updateBrightness() }
        .onChange(of: scenePhase) { updateBrightness() }
        // Back to dark 10 s after the last touch.
        .task(id: awake && !paused ? lastTouch : nil) {
            guard awake, !paused else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { awake = false }
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .overlay(Capsule().strokeBorder(color.opacity(0.8), lineWidth: 1))
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// Dark only while asleep in the foreground; any other time the user's brightness is back.
    private func updateBrightness() {
        if !awake, !paused, scenePhase == .active {
            guard let screen else { return }
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 0
        } else {
            restoreBrightness()
        }
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        screen?.brightness = saved
        savedBrightness = nil
    }
}
