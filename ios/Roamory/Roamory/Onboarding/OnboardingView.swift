import RoamoryKit
import SwiftUI

/// Trip setup before recording (PRD §4): style, destination, trip type, length, optional details, then Start.
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
    @AppStorage(TripSettings.Key.lengthHours) private var lengthHours = 3
    @AppStorage(TripSettings.Key.details) private var details = ""
    @State private var step = Self.initialStep
    @State private var forward = true
    @State private var started = false
    /// How far an edge swipe has pulled the screen to the right; the content follows the finger.
    @State private var dragX: CGFloat = 0
    private let catalog = try? OnboardingCatalog.bundled()

    private static let steps: [(eyebrow: String, title: String)] = [
        ("Your style", "Which one feels like your trip?"),
        ("Destination", "Where to?"),
        ("The trip", "Who's coming along?"),
        ("How long", "How many hours today?"),
        ("Optional", "Anything else we should know?"),
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
                StepHeader(index: step, eyebrow: Self.steps[step].eyebrow, title: Self.steps[step].title,
                           count: Self.steps.count, onClose: onClose, onBack: step > 0 ? { back() } : nil)
                ZStack {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: dragX)
                .opacity(1 - min(dragX / 600, 0.4))
                AccentButton(title: step == Self.steps.count - 1 ? "Start recording" : "Continue",
                             enabled: canContinue, action: advance)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        // A swipe from the left edge toward the right goes back a step (on the first step, leaves setup), like a
        // navigation stack: the step follows the finger, then slides away or springs back. The edge zone keeps it
        // clear of the globe, the deck and the sliders.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard isEdgeSwipe(value) else { return }
                    dragX = max(0, value.translation.width)
                }
                .onEnded { value in
                    let commit = isEdgeSwipe(value)
                        && (value.translation.width > 100 || value.predictedEndTranslation.width > 240)
                    if commit && step == 0 {
                        onClose?()
                    } else if commit {
                        forward = false
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { dragX = 0; step -= 1 }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { dragX = 0 }
                    }
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
        case 3:
            TripLengthStep(hours: $lengthHours, style: Style(rawValue: style) ?? .cinematic)
        default:
            TripDetailsStep(details: $details)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: Style(rawValue: style) != nil
        case 1: !city.isEmpty
        case 2: !tripType.isEmpty
        case 3: TripLengthStep.range.contains(lengthHours)
        default: true
        }
    }

    private func isEdgeSwipe(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x < 44 && value.translation.width > abs(value.translation.height) * 1.5
    }

    private func advance() {
        guard step < Self.steps.count - 1 else {
            started = true
            return onStart()
        }
        forward = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step += 1 }
    }

    private func back() {
        guard step > 0 else { return }
        forward = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step -= 1 }
    }
}
