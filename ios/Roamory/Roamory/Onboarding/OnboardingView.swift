import RoamoryKit
import SwiftUI

/// Trip setup before recording (PRD §4): style, destination, trip type, then length and Start.
/// Choices are saved in the `DetectionSettings` keys, so each launch starts from the last trip's answers.
struct OnboardingView: View {
    var onStart: () -> Void

    @AppStorage(DetectionSettings.Key.style) private var style = Style.cinematic.rawValue
    @AppStorage(DetectionSettings.Key.continent) private var continent = "Asia"
    @AppStorage(DetectionSettings.Key.country) private var country = "Japan"
    @AppStorage(DetectionSettings.Key.city) private var city = "Kyoto"
    @AppStorage(DetectionSettings.Key.tripType) private var tripType = "honeymoon"
    @AppStorage(DetectionSettings.Key.lengthDays) private var lengthDays = 3
    @State private var step = Self.initialStep
    @State private var forward = true
    private let catalog = try? OnboardingCatalog.bundled()

    private static let steps: [(eyebrow: String, title: String)] = [
        ("Your style", "Which one feels like your trip?"),
        ("Destination", "Where to?"),
        ("The trip", "Who's coming along?"),
        ("How long", "How many days?"),
    ]

    /// Debug builds can open at a step with the launch argument `-onboardingStep N`.
    private static var initialStep: Int {
        #if DEBUG
        min(max(UserDefaults.standard.integer(forKey: "onboardingStep"), 0), steps.count - 1)
        #else
        0
        #endif
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    StepHeader(index: step, eyebrow: Self.steps[step].eyebrow, title: Self.steps[step].title)
                }
                .overlay(alignment: .topLeading) { backButton }
                ZStack {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                AccentButton(title: step == Self.steps.count - 1 ? "Start recording" : "Continue",
                             enabled: canContinue, action: advance)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        // A swipe from the left edge goes back a step, like a navigation stack.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.startLocation.x < 24, value.translation.width > 80 { back() }
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: step)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            StylePickerStep(style: $style)
        default:
            Text("Coming soon").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if step > 0 {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.chip, in: Circle())
            }
            .offset(y: 16)
            .accessibilityLabel("Back")
            .transition(.opacity)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: Style(rawValue: style) != nil
        case 1: !city.isEmpty
        case 2: !tripType.isEmpty
        default: lengthDays >= 1
        }
    }

    private func advance() {
        guard step < Self.steps.count - 1 else { return onStart() }
        forward = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step += 1 }
    }

    private func back() {
        guard step > 0 else { return }
        forward = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step -= 1 }
    }
}
