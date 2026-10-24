//
//  ZoomDial.swift
//  Roamory
//

import SwiftUI

/// Rotary zoom dial like the system Camera app: ticks on a shallow arc that slide under a fixed center marker.
struct ZoomDial: View {
    let zoom: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let presets: [CGFloat]

    /// Finger travel that doubles the zoom; the arc moves 1:1 with the finger at the center.
    static let pointsPerDoubling: CGFloat = 100
    static let height: CGFloat = 80

    private let radius: CGFloat = 500
    private let arcTop: CGFloat = 32

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = arcTop + radius
            let perDoubling = Self.pointsPerDoubling / radius
            let base = log2(zoom)

            // Translucent disc; only its top edge is visible.
            context.fill(
                Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)),
                with: .color(.black.opacity(0.35)))

            func drawTick(_ z: CGFloat, length: CGFloat, width: CGFloat, label: String? = nil) {
                let angle = (log2(z) - base) * perDoubling
                let x = radius * sin(angle)
                let fade = max(0, 1 - pow(x / (size.width / 2), 2))
                guard fade > 0.02 else { return }
                var c = context
                c.opacity = fade
                c.translateBy(x: cx, y: cy)
                c.rotate(by: .radians(Double(angle)))
                c.fill(Path(CGRect(x: -width / 2, y: -radius + 4, width: width, height: length)), with: .color(.white))
                if let label {
                    c.draw(Text(label).font(.caption2.bold()).foregroundStyle(.white),
                           at: CGPoint(x: 0, y: -radius + 4 + length + 11))
                }
            }

            // Minor ticks every tenth of a doubling, skipping the ones under a labeled preset.
            let presetLogs = presets.map { log2($0) }
            for t in stride(from: log2(minZoom), through: log2(maxZoom) + 0.001, by: 0.1) {
                if presetLogs.contains(where: { abs($0 - t) < 0.03 }) { continue }
                drawTick(pow(2, t), length: 8, width: 1)
            }
            for z in presets {
                drawTick(z, length: 14, width: 1.5, label: String(format: "%g", z))
            }

            // Fixed center marker and live value.
            context.fill(Path(CGRect(x: cx - 1.5, y: arcTop + 4, width: 3, height: 24)), with: .color(.yellow))
            context.draw(Text(Self.label(zoom) + "x").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.yellow),
                         at: CGPoint(x: cx, y: 12))
        }
        .frame(height: Self.height)
    }

    /// "1" at a whole step, otherwise one decimal ("1.7").
    static func label(_ zoom: CGFloat) -> String {
        let rounded = (zoom * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded)
    }
}
