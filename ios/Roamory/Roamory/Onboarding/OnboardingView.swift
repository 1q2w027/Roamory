import RoamoryKit
import SwiftUI

/// Trip setup before recording (PRD §4): style, destination, trip type, then length and Start.
/// Choices are saved in the `TripSettings` keys, so each launch starts from the last trip's answers.
struct OnboardingView: View {
    var onStart: () -> Void
    /// The X at the top left: leaves setup without starting.
    var onClose: (() -> Void)?

    @AppStorage(TripSettings.Key.style) private var style = Style.cinematic.rawValue
    @AppStorage(TripSettings.Key.continent) private var continent = OnboardingCatalog.defaultContinent
    @AppStorage(TripSettings.Key.country) private var country = OnboardingCatalog.defaultCountry
    @AppStorage(TripSettings.Key.city) private var city = OnboardingCatalog.defaultCity
    @AppStorage(TripSettings.Key.tripType) private var tripType = "honeymoon"
    @AppStorage(TripSettings.Key.lengthDays) private var lengthDays = 3
    @State private var step = Self.initialStep
    @State private var started = false
    private let catalog = try? OnboardingCatalog.bundled()

    private static let steps: [(eyebrow: String, title: String, mood: RoamyMascot.Mood)] = [
        ("Your style", "Which one feels like your trip?", .excited),
        ("Destination", "Where are we off to?", .wave),
        ("The trip", "Who's coming along?", .happy),
        ("How long", "How many days?", .excited),
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
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(index: step, eyebrow: Self.steps[step].eyebrow, title: Self.steps[step].title,
                           mood: Self.steps[step].mood,
                           onClose: onClose, onBack: step > 0 ? { back() } : nil)
                // Everything under the question fades in quickly each time a step opens.
                ZStack {
                    stepContent
                        .modifier(QuickFadeIn())
                        .id(step)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.1))))
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
        .sensoryFeedback(.impact(weight: .heavy), trigger: started) { _, new in new }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            StylePickerStep(style: $style)
        case 1:
            if let catalog {
                DestinationStep(catalog: catalog, continent: $continent, country: $country, city: $city)
            }
        case 2:
            if let catalog { TripTypeStep(types: catalog.tripTypes, tripType: $tripType) }
        default:
            TripLengthStep(days: $lengthDays, style: Style(rawValue: style) ?? .cinematic)
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
        guard step < Self.steps.count - 1 else {
            started = true
            return onStart()
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step += 1 }
    }

    private func back() {
        guard step > 0 else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step -= 1 }
    }
}

/// Starts hidden and a little low, then fades up into place.
private struct QuickFadeIn: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { shown = true } }
    }
}
