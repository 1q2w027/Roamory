//
//  RoamyMascot.swift
//  Roamory
//

import SwiftUI

/// Roamy: a round green camera with a face. Bobs gently, blinks now and then, and changes face with its mood.
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
                .fill(Color(hex: "#01a84c"))
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
                .fill(Theme.accent)
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
                    .foregroundStyle(i == 1 ? Theme.accent : Theme.accent2)
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
