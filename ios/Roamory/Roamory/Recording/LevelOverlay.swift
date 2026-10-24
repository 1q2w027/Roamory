//
//  LevelOverlay.swift
//  Roamory
//

import RoamoryKit
import SwiftUI

/// The mount level over the camera preview, like the Camera app's: a horizon line that tilts and drifts with the
/// phone against a fixed crosshair, so the whole frame stays visible. Prompts instead when the phone is turned the
/// wrong way. It takes no touches; the level button closes it.
struct LevelOverlay: View {
    let pose: LevelPose?
    let isLevel: Bool
    /// Degrees off level at which the horizon reaches its farthest drift.
    let bubbleRangeDeg: Double
    /// The caption names only what is beyond the level tolerance, per axis.
    let toleranceDeg: Double
    let aimToleranceDeg: Double

    var body: some View {
        Group {
            switch pose {
            case .turnSideways: prompt("Turn the phone sideways", systemImage: "rotate.right")
            case .holdUpright: prompt("Hold the phone upright", systemImage: "rotate.right")
            case .turnOver: prompt("Turn the phone the other way round", systemImage: "arrow.triangle.2.circlepath")
            case .aligned(let tilt, let aim): horizon(tilt: tilt, aim: aim)
            case nil: horizon(tilt: nil, aim: nil)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: isLevel)
    }

    private var color: Color { isLevel ? Theme.accent : .white }

    private func horizon(tilt: Double?, aim: Double?) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxDrift = min(120, geo.size.height / 4)
            // The real horizon: it rises on the side that is high and drops when the camera aims up.
            let drift = CGFloat(min(max((aim ?? 0) / bubbleRangeDeg, -1), 1)) * maxDrift
            // The crosshair's upright bar spans the aim that still counts as level.
            let aimZone = CGFloat(min(aimToleranceDeg / bubbleRangeDeg, 1)) * maxDrift
            let lineLength = geo.size.width * 0.5
            let stubInset = geo.size.width * 0.1
            ZStack {
                // Level reference: stubs at the edges and a crosshair in the middle.
                stub.position(x: stubInset + 12, y: center.y)
                stub.position(x: geo.size.width - stubInset - 12, y: center.y)
                crosshair(aimZone: aimZone).position(center)
                ZStack {
                    Capsule()
                        .fill(color)
                        .frame(width: lineLength, height: isLevel ? 3 : 2)
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .background(Circle().fill(isLevel ? color : .clear))
                        .frame(width: 14, height: 14)
                }
                .shadow(color: .black.opacity(0.6), radius: 2)
                .rotationEffect(.degrees(-(tilt ?? 0)))
                .position(x: center.x, y: center.y + drift)
                .animation(.interactiveSpring, value: drift)
                .animation(.interactiveSpring, value: tilt)
                caption(tilt: tilt, aim: aim)
                    .position(x: center.x, y: center.y + maxDrift + 44)
            }
        }
        .ignoresSafeArea()
    }

    private var stub: some View {
        Capsule()
            .fill(color.opacity(0.8))
            .frame(width: 24, height: 2)
            .shadow(color: .black.opacity(0.6), radius: 2)
    }

    private func crosshair(aimZone: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: 22, height: 1.5)
            Capsule().frame(width: 1.5, height: max(22, aimZone * 2))
            // Short caps mark the ends of the aim zone.
            Capsule().frame(width: 10, height: 1.5).offset(y: -aimZone)
            Capsule().frame(width: 10, height: 1.5).offset(y: aimZone)
        }
        .foregroundStyle(color.opacity(0.8))
        .shadow(color: .black.opacity(0.6), radius: 2)
    }

    /// "Level" once level, otherwise only the readings beyond tolerance, each with the way to turn.
    @ViewBuilder
    private func caption(tilt: Double?, aim: Double?) -> some View {
        if isLevel {
            pill { Label("Level", systemImage: "checkmark") }
        } else if let tilt, let aim, tiltArrow(tilt) != nil || aimArrow(aim) != nil {
            pill {
                HStack(spacing: 12) {
                    if let arrow = tiltArrow(tilt) {
                        HStack(spacing: 4) { Text(String(format: "Tilt %.0f°", abs(tilt))); Image(systemName: arrow) }
                    }
                    if let arrow = aimArrow(aim) {
                        HStack(spacing: 4) { Text(String(format: "Aim %.0f°", abs(aim))); Image(systemName: arrow) }
                    }
                }
            }
        }
    }

    private func pill(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: Capsule())
            .fixedSize()
    }

    private func prompt(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
    }

    /// Right side low: turn counterclockwise to raise it.
    private func tiltArrow(_ tilt: Double) -> String? {
        tilt > toleranceDeg ? "arrow.counterclockwise" : tilt < -toleranceDeg ? "arrow.clockwise" : nil
    }

    /// Camera aimed up: aim it down.
    private func aimArrow(_ aim: Double) -> String? {
        aim > aimToleranceDeg ? "arrow.down" : aim < -aimToleranceDeg ? "arrow.up" : nil
    }
}

#Preview {
    ZStack {
        Color.gray
        LevelOverlay(pose: .aligned(tilt: 4, aim: 3), isLevel: false, bubbleRangeDeg: 10, toleranceDeg: 2.5,
                     aimToleranceDeg: 5)
    }
}
