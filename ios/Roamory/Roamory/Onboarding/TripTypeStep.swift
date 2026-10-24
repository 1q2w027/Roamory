import RoamoryKit
import SwiftUI

/// Step 3 (PRD FR-003): a deck of trip-type cards. Swipe the top card away and the one behind tilts forward;
/// the card on top is the choice. The deck never runs out: a swiped card goes to the back.
struct TripTypeStep: View {
    let types: [TripType]
    @Binding var tripType: String
    /// Card ids, top first. The single source of truth for the deck, so fast swipes cannot skip or repeat a card.
    @State private var order: [String] = []
    @State private var drag: CGSize = .zero
    /// Swiped cards still flying off screen.
    @State private var flying: [FlyingCard] = []

    private struct FlyingCard: Identifiable {
        let id = UUID()
        let type: TripType
        let from: CGSize
        let direction: CGFloat
    }

    private var progress: CGFloat { min(abs(drag.width) / 150, 1) }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.86, 330)
            let height = min(geo.size.height - 48, width * 1.3)
            VStack(spacing: 18) {
                ZStack {
                    glow
                    ForEach(Array(order.prefix(3).enumerated().reversed()), id: \.element) { slot, id in
                        if let type = types.first(where: { $0.id == id }) {
                            card(type, slot: slot)
                                .frame(width: width, height: height)
                                // A swiped card leaves at once; its `FlyAway` copy does the exit.
                                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                        }
                    }
                    ForEach(flying) { card in
                        FlyAway(from: card.from, direction: card.direction) {
                            TripCard(type: card.type, hint: nil)
                                .frame(width: width, height: height)
                        } onDone: {
                            flying.removeAll { $0.id == card.id }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                dots
            }
        }
        .onAppear {
            guard order.isEmpty else { return }
            let ids = types.map(\.id)
            let start = ids.firstIndex(of: tripType) ?? 0
            order = Array(ids[start...] + ids[..<start])
            if let first = order.first { tripType = first }
        }
        .sensoryFeedback(.selection, trigger: tripType)
    }

    /// A soft light in the top card's color.
    private var glow: some View {
        let color = types.first { $0.id == order.first }.map { Color(hex: $0.colors[0]) } ?? .clear
        return Circle()
            .fill(color.opacity(0.35))
            .blur(radius: 80)
            .scaleEffect(1.1)
            .animation(.easeInOut(duration: 0.5), value: order.first)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func card(_ type: TripType, slot: Int) -> some View {
        let isTop = slot == 0
        // Each card behind moves toward the slot in front of it as the top card is dragged away.
        let s = isTop ? 0 : CGFloat(slot) - progress
        let tilt: Double = slot == 1 ? -5 : 3.5
        TripCard(type: type, hint: isTop ? hint : nil)
            .rotation3DEffect(.degrees(isTop ? 0 : Double(s) * 8), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
            .scaleEffect(1 - s * 0.06)
            .offset(y: s * 14)
            .rotationEffect(.degrees(isTop ? Double(drag.width / 20) : tilt * Double(s)), anchor: .bottom)
            .offset(isTop ? drag : .zero)
            .shadow(color: .black.opacity(isTop ? 0.5 : 0.25), radius: isTop ? 20 : 10, y: 12)
            .zIndex(Double(10 - slot))
            .gesture(swipe, including: isTop ? .all : .none)
            .onTapGesture { if isTop { dismiss(direction: -1) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isTop ? .isSelected : [])
            .accessibilityAction(named: "Next") { dismiss(direction: -1) }
    }

    private var hint: String {
        let next = order.dropFirst().prefix(3).compactMap { id in types.first { $0.id == id }?.title.lowercased() }
        return "Swipe for more · " + next.joined(separator: ", ") + "…"
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 120 || abs(value.predictedEndTranslation.width) > 250 {
                    dismiss(direction: value.translation.width < 0 ? -1 : 1)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func dismiss(direction: CGFloat) {
        guard let top = order.first, let type = types.first(where: { $0.id == top }) else { return }
        flying.append(FlyingCard(type: type, from: drag, direction: direction))
        var next = order
        next.append(next.removeFirst())
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            order = next
            drag = .zero
        }
        tripType = next[0]
    }

    /// One dot per trip type; tapping a dot brings that card to the top.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(types) { type in
                Button {
                    guard let i = order.firstIndex(of: type.id), i > 0 else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        order = Array(order[i...] + order[..<i])
                    }
                    tripType = type.id
                } label: {
                    Capsule()
                        .fill(type.id == order.first ? Color(hex: type.colors[0]) : Theme.chip)
                        .frame(width: type.id == order.first ? 22 : 8, height: 8)
                        .padding(.vertical, 8)
                }
                .accessibilityLabel(type.title)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: order.first)
    }
}

/// A swiped card: starts where the finger let go and flies off that side, turning as it goes.
private struct FlyAway<Content: View>: View {
    let from: CGSize
    let direction: CGFloat
    @ViewBuilder let content: () -> Content
    let onDone: () -> Void
    @State private var gone = false

    var body: some View {
        content()
            .rotationEffect(.degrees(gone ? Double(direction) * 25 : Double(from.width / 20)), anchor: .bottom)
            .offset(x: gone ? direction * 600 : from.width, y: gone ? from.height + 60 : from.height)
            .opacity(gone ? 0 : 1)
            .zIndex(20)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeIn(duration: 0.35)) { gone = true } completion: { onDone() }
            }
    }
}

/// The illustrated card: the type's gradient, a floating emoji, its name and a line about it.
struct TripCard: View {
    let type: TripType
    let hint: String?
    @State private var float = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: type.colors.map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            Text(type.emoji)
                .font(.system(size: 72))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
                .offset(y: float ? -6 : 6)
                .rotationEffect(.degrees(float ? -4 : 4))
                .padding(24)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { float = true }
                }
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(type.title)
                    .font(.system(size: 36, weight: .heavy))
                Text(type.subtitle)
                    .font(.headline)
                    .opacity(0.9)
                if let hint {
                    Text(hint)
                        .font(.footnote)
                        .opacity(0.75)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
