import SwiftUI

/// The first-launch intro: four full-screen pages swiped vertically, with Roamy, the camera mascot, over slowly
/// breathing green and blue light. Shown once; Skip or the last page's button goes to Create.
struct WelcomeView: View {
    var onDone: () -> Void

    @State private var page = 0
    @State private var drag: CGFloat = 0
    @State private var finished = false

    private struct Page {
        let mood: RoamyMascot.Mood
        let title: String
        let body: String
        let badge: (icon: String, text: String)
    }

    private static let pages: [Page] = [
        Page(mood: .wave, title: "Hey, I'm Roamy!",
             body: "I film your trip so you can put the phone away and actually enjoy it.",
             badge: ("hand.wave.fill", "Nice to meet you")),
        Page(mood: .sleepy, title: "Pocket it. I've got this.",
             body: "The screen stays dark while I record quietly in the background, easy on your battery.",
             badge: ("moon.stars.fill", "Screen-off recording")),
        Page(mood: .excited, title: "Tap to keep a moment",
             body: "Press the star, a volume key or your Bluetooth button, and that moment is saved for sure.",
             badge: ("star.fill", "Guaranteed keeps")),
        Page(mood: .happy, title: "Your highlight reel, ready",
             body: "I pick the best bits and cut them into a video for you to watch, tweak and share.",
             badge: ("sparkles", "Made for you")),
    ]

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
            RoamyMascot(mood: p.mood)
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

/// Black, with a green and a blue glow that slowly swell and drift, like a breathing exercise.
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
                .fill(Theme.blue)
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

/// Roamy: a round green-to-blue camera with a face. Bobs gently, blinks now and then, and changes face with its mood.
struct RoamyMascot: View {
    enum Mood { case wave, sleepy, excited, happy }

    var mood: Mood
    var size: CGFloat = 170
    @State private var bob = false
    @State private var blink = false
    @State private var wave = false

    var body: some View {
        ZStack {
            // Lens bump on top.
            Capsule()
                .fill(Theme.accentLip)
                .frame(width: size * 0.34, height: size * 0.2)
                .offset(x: size * 0.18, y: -size * 0.4)
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: size, height: size * 0.84)
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: size * 0.22, height: size * 0.07)
                        .rotationEffect(.degrees(-20))
                        .offset(x: size * 0.14, y: size * 0.12)
                }
                .shadow(color: Theme.accent.opacity(0.6), radius: 30, y: 10)
            face
            accessories
        }
        .frame(width: size * 1.4, height: size * 1.2)
        .offset(y: bob ? -6 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { wave = true }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.2...4)))
                withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .seconds(0.12))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
        .accessibilityHidden(true)
    }

    private var face: some View {
        VStack(spacing: size * 0.07) {
            HStack(spacing: size * 0.22) { eye; eye }
            mouth
        }
        .overlay {
            HStack(spacing: size * 0.5) { cheek; cheek }.offset(y: size * 0.07)
        }
        .offset(y: size * 0.02)
    }

    @ViewBuilder
    private var eye: some View {
        if mood == .sleepy {
            SmileArc().stroke(.white, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.07)
        } else {
            Ellipse()
                .fill(.white)
                .frame(width: size * 0.2, height: size * 0.24)
                .overlay {
                    Circle()
                        .fill(Color.black)
                        .frame(width: size * 0.11)
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(.white).frame(width: size * 0.04).offset(x: -size * 0.01, y: size * 0.01)
                        }
                        .offset(x: size * 0.02, y: mood == .excited ? -size * 0.03 : size * 0.02)
                }
                .scaleEffect(y: blink ? 0.08 : 1)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .excited:
            Ellipse().fill(Color.black.opacity(0.85))
                .frame(width: size * 0.18, height: size * 0.14)
                .overlay(alignment: .bottom) {
                    Ellipse().fill(Color(hex: "#f472b6")).frame(width: size * 0.1, height: size * 0.05).offset(y: -size * 0.015)
                }
        case .sleepy:
            Circle().fill(Color.black.opacity(0.7)).frame(width: size * 0.06)
        case .wave, .happy:
            SmileArc().stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.24, height: size * 0.09)
        }
    }

    private var cheek: some View {
        Ellipse().fill(Color(hex: "#ffb3c7").opacity(0.5)).frame(width: size * 0.12, height: size * 0.07)
    }

    @ViewBuilder
    private var accessories: some View {
        switch mood {
        case .wave:
            Capsule()
                .fill(Theme.blue)
                .frame(width: size * 0.14, height: size * 0.3)
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .rotationEffect(.degrees(wave ? 30 : -5), anchor: .bottom)
                .offset(x: size * 0.56, y: -size * 0.14)
        case .sleepy:
            ZStack {
                Text("z").font(.system(size: size * 0.14, weight: .heavy, design: .rounded)).offset(x: 0, y: 0)
                Text("z").font(.system(size: size * 0.2, weight: .heavy, design: .rounded)).offset(x: size * 0.14, y: -size * 0.16)
            }
            .foregroundStyle(Theme.accent2)
            .opacity(bob ? 1 : 0.4)
            .offset(x: -size * 0.55, y: -size * 0.42)
        case .excited:
            ForEach(0..<3) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: size * [0.16, 0.11, 0.13][i], weight: .bold))
                    .foregroundStyle(i == 1 ? Theme.blue : Theme.accent2)
                    .scaleEffect(wave ? 1.15 : 0.8)
                    .offset(x: size * [-0.62, 0.62, 0.55][i], y: size * [-0.35, -0.38, 0.32][i])
            }
        case .happy:
            Image(systemName: "film.stack.fill")
                .font(.system(size: size * 0.2))
                .foregroundStyle(.white, Theme.accent2)
                .rotationEffect(.degrees(wave ? 8 : -8))
                .offset(x: size * 0.6, y: size * 0.32)
        }
    }
}

/// The lower half of an ellipse: a smile, or closed sleepy eyes.
private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
        return path
    }
}

#Preview {
    WelcomeView {}
}
