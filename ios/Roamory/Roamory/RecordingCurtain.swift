import SwiftUI
import UIKit

/// Recording mode (PRD FR-007, mockup screen 4): a black screen at 0% brightness over the camera UI.
/// Hold to wake it; it goes dark again after 10 s without a touch. A kept moment flashes it dim red.
struct RecordingCurtain: View {
    let summary: DetectionSummary
    /// Bookmark, volume key and remote presses, for the flash.
    let buttonPresses: Int
    @Binding var awake: Bool
    /// When the camera UI under the curtain was last touched; restarts the 10 s countdown.
    let lastTouch: Date

    @Environment(\.scenePhase) private var scenePhase
    @State private var savedBrightness: CGFloat?
    @State private var holdProgress: CGFloat = 0
    @State private var flash = false
    @State private var pulse = false
    @State private var bump = false

    private var kept: Int { summary.keptAI + summary.keptButton + summary.keptFallback }

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
                pill("Moments kept · \(kept)", color: bump ? Theme.accent : .white.opacity(0.35))
                    .scaleEffect(bump ? 1.12 : 1)
                    .contentTransition(.numericText(value: Double(kept)))
                Spacer()
                Text("Shutter remote or volume key: press = this moment goes in the video")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
            }
            Theme.recording
                .opacity(flash ? 0.28 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .opacity(awake ? 0 : 1)
        .allowsHitTesting(!awake)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            holdProgress = 0
            withAnimation(.easeOut(duration: 0.35)) { awake = true }
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 0.6) : .easeOut(duration: 0.2)) { holdProgress = pressing ? 1 : 0 }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: awake)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            updateBrightness()
        }
        .onDisappear(perform: restoreBrightness)
        .onChange(of: awake) { updateBrightness() }
        .onChange(of: scenePhase) { updateBrightness() }
        .onChange(of: buttonPresses) {
            flash = true
            withAnimation(.easeOut(duration: 0.8)) { flash = false }
        }
        .onChange(of: kept) { old, new in
            guard new > old else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bump = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) { bump = false }
        }
        // Back to dark 10 s after the last touch.
        .task(id: awake ? lastTouch : nil) {
            guard awake else { return }
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
        if !awake, scenePhase == .active {
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
