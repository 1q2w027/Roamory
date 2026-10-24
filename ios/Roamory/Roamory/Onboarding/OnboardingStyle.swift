import SwiftUI

/// Green (#03fc73), blue and black.
enum Theme {
    static let background = Color(hex: "#08080a")
    static let accent = Color(hex: "#03fc73")
    static let blue = Color(hex: "#3b82f6")
    /// Light green for eyebrows and pin heads.
    static let accent2 = Color(hex: "#8dffbe")
    /// Text on the accent: dark, since the green is bright.
    static let accentInk = Color(hex: "#02200f")
    /// The darker edge under a chunky button.
    static let accentLip = Color(hex: "#01a84c")
    static let card = Color(hex: "#141416")
    static let chip = Color(hex: "#222226")
    static let secondaryText = Color(hex: "#8e8e99")
    static let recording = Color(hex: "#ff3b30")

    static let accentGradient = LinearGradient(colors: [accent, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// `#rrggbb`; anything else is gray.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}

/// A progress bar that fills as the steps go by, "1 OF 4 · YOUR STYLE", and Roamy asking the question in a speech bubble.
struct StepHeader: View {
    let index: Int
    let eyebrow: String
    let title: String
    var count = 4
    var mood: RoamyMascot.Mood = .happy
    /// Shows an X at the start of the progress bar that leaves setup.
    var onClose: (() -> Void)?
    /// Shows a back chevron at the start of the progress bar.
    var onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let onClose {
                    circleButton("xmark", label: "Close", action: onClose)
                }
                if let onBack {
                    circleButton("chevron.left", label: "Back", action: onBack)
                        .transition(.scale.combined(with: .opacity))
                }
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Theme.accent : Theme.chip)
                        .frame(height: 4)
                        .frame(maxWidth: i == index ? .infinity : 28)
                }
            }
            .padding(.bottom, 6)
            .padding(.trailing, 56) // clear of the corner button
            Text("\(index + 1) OF \(count) · \(eyebrow.uppercased())")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .tracking(2)
                .foregroundStyle(Theme.accent2)
            HStack(alignment: .center, spacing: 4) {
                RoamyMascot(mood: mood, size: 58)
                    .frame(width: 74, height: 70)
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SpeechBubble().fill(Theme.card))
                    .overlay(SpeechBubble().stroke(.white.opacity(0.08)))
                    .id(title)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 16)), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: index)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.chip, in: Circle())
        }
        .padding(.trailing, 4)
        .accessibilityLabel(label)
    }
}

/// The green Continue button.
struct AccentButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
        }
        .buttonStyle(ChunkyStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

/// A raised button on a darker lip that sinks onto it while pressed.
struct ChunkyStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var lip: Color = Theme.accentLip
    private let depth: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .background(fill, in: shape)
            .offset(y: configuration.isPressed ? depth : 0)
            .background(lip, in: shape.offset(y: depth))
            .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Shrinks a little while pressed, with a light tap.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A rounded box with a small tail on its left edge, pointing at Roamy.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 10
        var path = Path(roundedRect: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height),
                        cornerRadius: 18, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + tail, y: rect.midY - 8))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + tail, y: rect.midY + 8))
        path.closeSubpath()
        return path
    }
}
