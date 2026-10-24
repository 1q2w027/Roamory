//
//  LevelOverlay.swift
//  Roamory
//

import RoamoryKit
import SwiftUI

/// The mount level over the camera preview: a bubble in a ring, big enough to read at a glance from above on a
/// chest mount, or a prompt when the phone is turned the wrong way.
struct LevelOverlay: View {
    let pose: LevelPose?
    let isLevel: Bool
    /// Degrees off level at which the bubble reaches the ring.
    let bubbleRangeDeg: Double
    /// Arrows show only beyond the level tolerance.
    let toleranceDeg: Double

    private static let ringSize: CGFloat = 220
    private static let bubbleSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 16) {
            switch pose {
            case .turnSideways: prompt("Turn the phone sideways", systemImage: "rotate.right")
            case .holdUpright: prompt("Hold the phone upright", systemImage: "rotate.right")
            case .turnOver: prompt("Turn the phone the other way round", systemImage: "arrow.triangle.2.circlepath")
            case .aligned(let tilt, let aim): level(tilt: tilt, aim: aim)
            case nil: level(tilt: nil, aim: nil)
            }
            Text("Tap to close")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 28))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .animation(.easeOut(duration: 0.2), value: isLevel)
    }

    private var color: Color { isLevel ? Theme.accent : .white }

    private func level(tilt: Double?, aim: Double?) -> some View {
        let radius = (Self.ringSize - Self.bubbleSize) / 2
        // The bubble sits on the high side and rises when the camera aims up.
        var offset = CGSize(width: -(tilt ?? 0) / bubbleRangeDeg * radius, height: -(aim ?? 0) / bubbleRangeDeg * radius)
        let length = hypot(offset.width, offset.height)
        if length > radius { offset = CGSize(width: offset.width / length * radius, height: offset.height / length * radius) }
        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 6)
                    .frame(width: Self.ringSize, height: Self.ringSize)
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .frame(width: Self.bubbleSize + 12, height: Self.bubbleSize + 12)
                Circle()
                    .fill(color)
                    .frame(width: Self.bubbleSize, height: Self.bubbleSize)
                    .offset(offset)
                    .animation(.interactiveSpring, value: offset)
            }
            if let tilt, let aim {
                HStack(spacing: 12) {
                    if let arrow = tiltArrow(tilt) { Image(systemName: arrow) }
                    Text(String(format: "Tilt %.0f° · Aim %.0f°", abs(tilt), abs(aim)))
                    if let arrow = aimArrow(aim) { Image(systemName: arrow) }
                }
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            }
        }
    }

    private func prompt(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .semibold))
            Text(text)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(width: Self.ringSize)
        .padding(.vertical, 24)
    }

    /// Right side low: turn counterclockwise to raise it.
    private func tiltArrow(_ tilt: Double) -> String? {
        tilt > toleranceDeg ? "arrow.counterclockwise" : tilt < -toleranceDeg ? "arrow.clockwise" : nil
    }

    /// Camera aimed up: aim it down.
    private func aimArrow(_ aim: Double) -> String? {
        aim > toleranceDeg ? "arrow.down" : aim < -toleranceDeg ? "arrow.up" : nil
    }
}
