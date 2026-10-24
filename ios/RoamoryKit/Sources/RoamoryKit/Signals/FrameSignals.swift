import Foundation

/// Cheap per-sample signals (TRD 6). No ML; plain loops over a small grayscale frame.
public struct FrameSignals: Sendable, Equatable {
    /// Variance of the 4-neighbor Laplacian over interior pixels; higher is sharper.
    public var sharpness: Double
    public var meanLuma: Double
    /// Share of pixels under 16 or over 240.
    public var clippedFraction: Double
    /// Mean absolute difference from the previous sample; 0 without one.
    public var change: Double
    /// 64-bit difference hash: 9×8 box average, bit set where a cell is darker than its right neighbor, MSB first.
    public var dhash: UInt64

    public init(sharpness: Double, meanLuma: Double, clippedFraction: Double, change: Double, dhash: UInt64) {
        self.sharpness = sharpness
        self.meanLuma = meanLuma
        self.clippedFraction = clippedFraction
        self.change = change
        self.dhash = dhash
    }

    public static func compute(_ frame: LumaFrame, previous: LumaFrame?) -> FrameSignals {
        let w = frame.width, h = frame.height, p = frame.pixels
        let n = Double(p.count)

        var sum = 0.0, clipped = 0
        for v in p {
            sum += Double(v)
            if v < 16 || v > 240 { clipped += 1 }
        }

        var lapSum = 0.0, lapSq = 0.0, lapCount = 0.0
        if w >= 3, h >= 3 {
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let i = y * w + x
                    let r = Double(p[i - w]) + Double(p[i + w]) + Double(p[i - 1]) + Double(p[i + 1]) - 4 * Double(p[i])
                    lapSum += r
                    lapSq += r * r
                    lapCount += 1
                }
            }
        }
        let sharpness = lapCount > 0 ? lapSq / lapCount - (lapSum / lapCount) * (lapSum / lapCount) : 0

        var change = 0.0
        if let prev = previous, prev.width == w, prev.height == h {
            var diff = 0.0
            for i in 0..<p.count { diff += abs(Double(p[i]) - Double(prev.pixels[i])) }
            change = diff / n
        }

        return FrameSignals(
            sharpness: max(sharpness, 0), meanLuma: n > 0 ? sum / n : 0,
            clippedFraction: n > 0 ? Double(clipped) / n : 0, change: change, dhash: dhash(frame)
        )
    }

    static func dhash(_ frame: LumaFrame) -> UInt64 {
        let cols = 9, rows = 8
        guard frame.width >= cols, frame.height >= rows else { return 0 }
        var cells = [[Double]](repeating: [Double](repeating: 0, count: cols), count: rows)
        for r in 0..<rows {
            let y0 = r * frame.height / rows, y1 = (r + 1) * frame.height / rows
            for c in 0..<cols {
                let x0 = c * frame.width / cols, x1 = (c + 1) * frame.width / cols
                var s = 0.0
                for y in y0..<y1 { for x in x0..<x1 { s += Double(frame.pixels[y * frame.width + x]) } }
                cells[r][c] = s / Double((y1 - y0) * (x1 - x0))
            }
        }
        var hash: UInt64 = 0
        for r in 0..<rows {
            for c in 0..<(cols - 1) {
                hash = (hash << 1) | (cells[r][c] < cells[r][c + 1] ? 1 : 0)
            }
        }
        return hash
    }
}

/// Number of differing bits between two dHashes.
public func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    (a ^ b).nonzeroBitCount
}
