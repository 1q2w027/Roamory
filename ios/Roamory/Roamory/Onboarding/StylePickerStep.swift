import AVFoundation
import RoamoryKit
import SwiftUI

/// Step 1 (PRD FR-001): four sample clips loop silently; tapping one chooses it and grows it to fill the step with sound.
struct StylePickerStep: View {
    @Binding var style: String
    /// True while a clip is open fullscreen; setup shows Continue only then.
    @Binding var isExpanded: Bool
    @State private var expanded: Style?
    @State private var players: [Style: LoopingPlayer] = [:]
    @State private var dragDown: CGFloat = 0
    @Namespace private var namespace
    private let presets = try? StylePresets.bundled()

    /// Grid order, as in the mockup.
    static let order: [Style] = [.reels, .cinematic, .documentary, .vlog]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let width = (geo.size.width - spacing) / 2
            // Cards fill the height the step has (Continue is hidden here), leaving room for the footnote.
            let height = max(120, (geo.size.height - spacing - 56) / 2)
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                        GridRow { card(Self.order[0], width: width, height: height); card(Self.order[1], width: width, height: height) }
                        GridRow { card(Self.order[2], width: width, height: height); card(Self.order[3], width: width, height: height) }
                    }
                    Text("Tap one to choose it and watch it with sound.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .opacity(expanded == nil ? 1 : 0)
                }
                if let expanded {
                    expandedCard(expanded, size: geo.size)
                        .zIndex(1)
                }
            }
        }
        .onAppear {
            isExpanded = false
            makePlayers()
            #if DEBUG
            // `-expandStyle reels` opens that style's clip, for screenshots.
            if let s = UserDefaults.standard.string(forKey: "expandStyle").flatMap(Style.init(rawValue:)) { expand(s) }
            #endif
        }
        .onDisappear {
            players.values.forEach { $0.player.pause() }
            players = [:]
        }
        .sensoryFeedback(.selection, trigger: style)
    }

    private func makePlayers() {
        guard players.isEmpty else { return }
        for style in Self.order {
            if let url = BundledResources.stylePreviewURL(style) { players[style] = LoopingPlayer(url: url) }
        }
    }

    @ViewBuilder
    private func card(_ s: Style, width: CGFloat, height: CGFloat) -> some View {
        let isSelected = style == s.rawValue
        Group {
            if expanded == s {
                Color.clear
            } else {
                Button { expand(s) } label: {
                    StyleTile(style: s, player: players[s]?.player, selected: isSelected, large: false)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .matchedGeometryEffect(id: s, in: namespace)
            }
        }
        .frame(width: width, height: height)
        .opacity(expanded == nil || expanded == s ? 1 : 0)
        .scaleEffect(expanded == nil || expanded == s ? 1 : 0.9)
        .blur(radius: expanded == nil || expanded == s ? 0 : 6)
    }

    private func expandedCard(_ s: Style, size: CGSize) -> some View {
        StyleTile(style: s, player: players[s]?.player, selected: style == s.rawValue, large: true,
                  detail: detail(for: s))
            .overlay(alignment: .topLeading) {
                Button { collapse() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
                .accessibilityLabel("Close")
            }
            .matchedGeometryEffect(id: s, in: namespace)
            .frame(width: size.width, height: size.height)
            .offset(y: max(0, dragDown))
            .scaleEffect(1 - min(dragDown, 300) / 1500)
            .onTapGesture { collapse() }
            .gesture(
                DragGesture()
                    .onChanged { dragDown = $0.translation.height }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                            collapse()
                        } else {
                            withAnimation(.spring) { dragDown = 0 }
                        }
                    }
            )
    }

    /// One line about the edit this style makes, from its preset.
    private func detail(for s: Style) -> String {
        guard let p = presets?[s] else { return s.subtitle }
        let format = p.output.isPortrait ? "9:16 upright" : "16:9 sideways"
        return "\(format) · \(Int(p.targetS.default)) s video · \(p.transition.rawValue) transitions"
    }

    /// Tapping a card chooses it, and opens it with sound.
    private func expand(_ s: Style) {
        style = s.rawValue
        // Off the main thread: the audio session can block long enough to hang the UI.
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
        }
        players[s]?.player.isMuted = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            expanded = s
            isExpanded = true
        }
    }

    private func collapse() {
        if let expanded { players[expanded]?.player.isMuted = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            expanded = nil
            isExpanded = false
            dragDown = 0
        }
    }
}

/// A style's clip under its mockup tint, with the name, a ▶ badge, and a glowing ring when chosen.
private struct StyleTile: View {
    let style: Style
    let player: AVPlayer?
    let selected: Bool
    let large: Bool
    var detail: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: large ? 28 : 20, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // The clip in black and white under the style's tint, so the four read as the mockup's colors.
            if let player {
                LoopingVideo(player: player)
                    .saturation(large ? 1 : 0)
                    .opacity(large ? 1 : 0.55)
                    .blendMode(large ? .normal : .overlay)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .font(large ? .largeTitle.bold() : .headline)
                Text(style.subtitle)
                    .font(large ? .body : .caption)
                    .opacity(0.85)
                if large, let detail {
                    Text(detail)
                        .font(.footnote.monospacedDigit())
                        .opacity(0.7)
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .padding(large ? 20 : 14)
        }
        .overlay(alignment: .topTrailing) {
            if !large {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(10)
            }
        }
        .clipShape(shape)
        .overlay { if selected { SelectionRing(shape: shape) } }
        .contentShape(shape)
    }
}

/// An accent ring whose highlight slowly travels around the card.
private struct SelectionRing<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360
            shape
                .strokeBorder(
                    AngularGradient(colors: [Theme.accent, Theme.accent2, .white, Theme.accent2, Theme.accent],
                                    center: .center, angle: .degrees(angle)),
                    lineWidth: 3
                )
        }
        .shadow(color: Theme.accent.opacity(0.6), radius: 14)
        .allowsHitTesting(false)
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
