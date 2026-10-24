import RoamoryKit
import SwiftUI

/// Step 4 (PRD FR-004, FR-007a): scrub a ruler to set the number of days, and see how to wear the phone for the style.
struct TripLengthStep: View {
    @Binding var days: Int
    let style: Style
    @State private var dragStartDays: Int?

    static let range = 1...30
    /// Points of drag per day.
    private static let tick: CGFloat = 24

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            counter
            ruler
            Spacer(minLength: 0)
            MountGuide(portrait: style == .reels)
        }
        .sensoryFeedback(.selection, trigger: days)
    }

    private var counter: some View {
        HStack(spacing: 24) {
            stepButton("minus", delta: -1)
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.accentGradient)
                    .contentTransition(.numericText(value: Double(days)))
                Text(days == 1 ? "day" : "days")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 140)
            stepButton("plus", delta: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: days)
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            days = min(max(days + delta, Self.range.lowerBound), Self.range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.chip, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(delta < 0 ? "Fewer days" : "More days")
    }

    /// Ticks for each day slide under a fixed center mark; drag left for more days.
    private var ruler: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(Self.range), id: \.self) { d in
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(d == days ? Theme.accent : .white.opacity(d % 7 == 0 ? 0.6 : 0.25))
                                .frame(width: d == days ? 3 : 2, height: d % 7 == 0 || d == days ? 28 : 16)
                            if d % 7 == 0 || d == 1 {
                                Text("\(d)").font(.caption2).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(width: Self.tick)
                    }
                }
                .offset(x: center - Self.tick / 2 - CGFloat(days - 1) * Self.tick)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: days)
            }
            .frame(width: geo.size.width, height: 52, alignment: .topLeading)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let start = dragStartDays ?? days
                        dragStartDays = start
                        let next = start - Int((value.translation.width / Self.tick).rounded())
                        days = min(max(next, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in dragStartDays = nil }
            )
        }
        .frame(height: 52)
        .accessibilityElement()
        .accessibilityLabel("Trip length")
        .accessibilityValue("\(days) days")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: days = min(days + 1, Self.range.upperBound)
            case .decrement: days = max(days - 1, Self.range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// How to wear the phone: a chest mount, camera out, turned the way the style records (PRD FR-007a).
private struct MountGuide: View {
    let portrait: Bool
    @State private var turned = false

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 34, height: 62)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: -8, y: -21)
            }
            .rotationEffect(.degrees(turned ? -90 : 0))
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text("Chest mount, camera facing out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(portrait ? "Hold it upright: Reels records 9:16." : "Turn it sideways: this style records 16:9.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .task(id: portrait) {
            turned = false
            guard !portrait else { return }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { turned = true }
        }
    }
}
