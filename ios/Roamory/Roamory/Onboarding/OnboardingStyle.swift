import SwiftUI

/// Colors from the mockup (docs/mockups/iphone-screens.html).
enum Theme {
    static let background = Color(hex: "#0b0b10")
    static let accent = Color(hex: "#03fc73")
    static let accent2 = Color(hex: "#8dffbe")
    /// Text on the accent gradient.
    static let accentInk = Color(hex: "#02200f")
    static let card = Color(hex: "#1a1a22")
    static let chip = Color(hex: "#22222c")
    static let secondaryText = Color(hex: "#8e8e99")
    static let recording = Color(hex: "#ff3b30")

    static let accentGradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    /// `#rrggbb`; anything else is gray.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}

/// "1 OF 4 · YOUR STYLE", the title, and a progress bar that fills as the steps go by.
struct StepHeader: View {
    let index: Int
    let eyebrow: String
    let title: String
    var count = 4
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
                        .fill(i <= index ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.chip))
                        .frame(height: 4)
                        .frame(maxWidth: i == index ? .infinity : 28)
                }
            }
            .padding(.bottom, 6)
            .padding(.trailing, 56) // clear of the corner button
            Text("\(index + 1) OF \(count) · \(eyebrow.uppercased())")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.accent2)
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .id(title)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
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
                .font(.headline)
                .foregroundStyle(Theme.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: Theme.accent.opacity(enabled ? 0.45 : 0), radius: 16, y: 6)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: enabled)
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
