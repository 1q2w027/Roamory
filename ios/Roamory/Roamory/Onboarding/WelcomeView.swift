import SwiftUI

/// The first-launch intro: four full-screen pages swiped vertically, each with a big glowing icon, over slowly
/// breathing green light. Shown once; Skip or the last page's button goes to Create.
struct WelcomeView: View {
    var onDone: () -> Void

    @State private var page = Self.initialPage
    @State private var drag: CGFloat = 0
    @State private var finished = false

    private struct Page {
        let title: String
        let body: String
        let badge: (icon: String, text: String)
    }

    private static let pages: [Page] = [
        Page(title: "Welcome to Roamory",
             body: "Roamory films your trip so you can put the phone away and actually enjoy it.",
             badge: ("hand.wave.fill", "Nice to meet you")),
        Page(title: "Pocket it",
             body: "The screen stays dark while Roamory records quietly in the background, easy on your battery.",
             badge: ("moon.stars.fill", "Screen-off recording")),
        Page(title: "Keep a moment",
             body: "Press Save, a volume key or your Bluetooth button, and the last 45 seconds are kept for sure.",
             badge: ("star.fill", "Guaranteed keeps")),
        Page(title: "Your trip, in one video",
             body: "Your saved clips wait in the Gallery, ready to be cut into a video to watch and share.",
             badge: ("sparkles", "Made for you")),
    ]

    /// Debug builds can open at a page with the launch argument `-welcomePage N`.
    private static var initialPage: Int {
        #if DEBUG
        min(max(UserDefaults.standard.integer(forKey: "welcomePage"), 0), pages.count - 1)
        #else
        0
        #endif
    }

    private var current: Int { page }
    private var isLast: Bool { current == Self.pages.count - 1 }

    var body: some View {
        ZStack {
            BreathingBackground()
            // A vertical pager: pages stacked full height, the drag follows the finger and snaps to a page.
            GeometryReader { geo in
                let height = geo.size.height
                VStack(spacing: 0) {
                    ForEach(Self.pages.indices, id: \.self) { i in
                        pageView(Self.pages[i], index: i)
                            .frame(width: geo.size.width, height: height)
                    }
                }
                .offset(y: -CGFloat(page) * height + drag)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Rubber-band past the first and last page.
                            let atEdge = (page == 0 && value.translation.height > 0)
                                || (isLast && value.translation.height < 0)
                            drag = value.translation.height * (atEdge ? 0.3 : 1)
                        }
                        .onEnded { value in
                            let flick = value.predictedEndTranslation.height
                            var next = page
                            if flick < -height / 4 { next += 1 } else if flick > height / 4 { next -= 1 }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                page = min(max(next, 0), Self.pages.count - 1)
                                drag = 0
                            }
                        }
                )
            }

            overlay
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: finished) { _, new in new }
    }

    private func pageView(_ p: Page, index: Int) -> some View {
        let shown = current == index
        return VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 150, height: 150)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 30, y: 10)
                Image(systemName: p.badge.icon)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Theme.accentInk)
            }
            .scaleEffect(shown ? 1 : 0.7)
                .opacity(shown ? 1 : 0)
            VStack(spacing: 14) {
                Label(p.badge.text, systemImage: p.badge.icon)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.accent2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
                Text(p.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
            }
            .offset(y: shown ? 0 : 24)
            .opacity(shown ? 1 : 0)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: shown)
    }

    /// Skip at the top, page dots down the right edge, and the button at the bottom.
    private var overlay: some View {
        VStack {
            HStack {
                Spacer()
                if !isLast {
                    Button("Skip", action: finish)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06), in: Capsule())
                        .transition(.opacity)
                }
            }
            .frame(height: 40)
            Spacer()
            VStack(spacing: 16) {
                if current == 0 { SwipeHint().transition(.opacity) }
                AccentButton(title: isLast ? "Let's plan my trip" : "Next") {
                    if isLast { finish() } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { page += 1 } }
                }
            }
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 8) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == current ? Theme.accent : .white.opacity(0.2))
                        .frame(width: 6, height: i == current ? 26 : 6)
                }
            }
            .offset(x: 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }

    private func finish() {
        finished = true
        onDone()
    }
}

/// "Swipe up" with a gently bouncing chevron.
private struct SwipeHint: View {
    @State private var up = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.up")
                .font(.footnote.weight(.bold))
                .offset(y: up ? -4 : 2)
            Text("Swipe up").font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(Theme.secondaryText)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

/// Black, with two green glows that slowly swell and drift, like a breathing exercise.
struct BreathingBackground: View {
    @State private var inhale = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.accent)
                .frame(width: 340, height: 340)
                .blur(radius: 110)
                .opacity(inhale ? 0.55 : 0.3)
                .scaleEffect(inhale ? 1.15 : 0.9)
                .offset(x: inhale ? -90 : -40, y: inhale ? -230 : -170)
            Circle()
                .fill(Theme.accent2)
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .opacity(inhale ? 0.3 : 0.5)
                .scaleEffect(inhale ? 0.95 : 1.2)
                .offset(x: inhale ? 110 : 70, y: inhale ? 260 : 200)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { inhale = true }
        }
    }
}

#Preview {
    WelcomeView {}
}
