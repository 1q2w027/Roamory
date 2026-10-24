import RoamoryKit
import SwiftUI

/// Step 1 (PRD FR-001): four cards, each a simple picture of what that edit looks like. Tapping one chooses it.
struct StylePickerStep: View {
    @Binding var style: String
    private let presets = try? StylePresets.bundled()

    static let order: [Style] = [.reels, .cinematic, .documentary, .vlog]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let width = (geo.size.width - spacing) / 2
            let height = max(120, min((geo.size.height - spacing - 56) / 2, width * 1.25))
            VStack(alignment: .leading, spacing: 16) {
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    GridRow { card(Self.order[0], width: width, height: height); card(Self.order[1], width: width, height: height) }
                    GridRow { card(Self.order[2], width: width, height: height); card(Self.order[3], width: width, height: height) }
                }
                if let chosen = Style(rawValue: style) {
                    Text(detail(for: chosen))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                        .id(chosen)
                        .transition(.opacity)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: style)
    }

    private func card(_ s: Style, width: CGFloat, height: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { style = s.rawValue }
        } label: {
            StyleTile(style: s, selected: style == s.rawValue)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .frame(width: width, height: height)
    }

    /// One line about the edit this style makes, from its preset.
    private func detail(for s: Style) -> String {
        guard let p = presets?[s] else { return s.subtitle }
        let format = p.output.isPortrait ? "9:16 upright" : "16:9 sideways"
        return "\(s.title): \(format) · \(Int(p.targetS.default)) s video · \(p.transition.rawValue) transitions"
    }
}

/// A dark card with the style's picture, its name, and a glowing ring when chosen.
private struct StyleTile: View {
    let style: Style
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            StyleArt(style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(selected ? 1.06 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title).font(.system(.headline, design: .rounded).weight(.bold))
                Text(style.subtitle).font(.system(.caption, design: .rounded)).foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(Theme.card)
        .overlay(alignment: .topTrailing) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Theme.accent : .white.opacity(0.25))
                .background(Circle().fill(selected ? .white : .clear).padding(3))
                .padding(10)
        }
        .clipShape(shape)
        .overlay { if selected { SelectionRing(shape: shape) } else { shape.strokeBorder(.white.opacity(0.06)) } }
        .contentShape(shape)
    }
}

/// Each edit as emojis: a big one for the style and two small ones around it.
private struct StyleArt: View {
    let style: Style
    @State private var float = false

    private var emojis: (main: String, left: String, right: String) {
        switch style {
        case .reels: ("📱", "⚡️", "🎵")
        case .cinematic: ("🎬", "🌄", "✨")
        case .documentary: ("🎙️", "📝", "🌍")
        case .vlog: ("🤳", "💬", "😄")
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.16)).frame(width: 96, height: 96).blur(radius: 10)
            Text(emojis.main).font(.system(size: 58))
            Text(emojis.left).font(.system(size: 26))
                .offset(x: -46, y: float ? -26 : -20)
            Text(emojis.right).font(.system(size: 24))
                .offset(x: 46, y: float ? 18 : 24)
        }
        .padding(.top, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

/// A green ring with a soft glow that slowly pulses.
private struct SelectionRing<S: InsettableShape>: View {
    let shape: S
    @State private var glow = false

    var body: some View {
        shape
            .strokeBorder(Theme.accent, lineWidth: 3)
            .shadow(color: Theme.accent.opacity(glow ? 0.8 : 0.35), radius: glow ? 16 : 8)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

extension Style {
    var title: String { rawValue.capitalized }

    var subtitle: String {
        switch self {
        case .reels: "fast cuts"
        case .cinematic: "slow, wide"
        case .documentary: "calm, captions"
        case .vlog: "casual"
        }
    }

    /// Tints from the mockup.
    var colors: [Color] {
        switch self {
        case .reels: [Color(hex: "#ff5f6d"), Color(hex: "#ffc371")]
        case .cinematic: [Color(hex: "#1f3a5f"), Color(hex: "#0b1020")]
        case .documentary: [Color(hex: "#5b7a5f"), Color(hex: "#c9b99a")]
        case .vlog: [Color(hex: "#6a85b6"), Color(hex: "#bac8e0")]
        }
    }
}
