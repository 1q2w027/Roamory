import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Phone-side pre-pass before planning (TRD 9.1 step 1): drop near-duplicates, pick each clip's best
/// sub-window, and make the thumbnails the cloud planner sees.
public enum PrePass {
    /// Dedupe, then set each clip's proposed window to the preset's default clip length.
    public static func run(_ clips: [ClipInfo], preset: StylePreset, config: EditConfig) -> [ClipInfo] {
        dedupe(clips, maxHamming: config.dedupeHamming).map { clip in
            var clip = clip
            (clip.proposedInS, clip.proposedOutS) = bestWindow(clip, lengthS: preset.clipS.default, config: config)
            return clip
        }
    }

    // MARK: Dedupe

    /// Two clips whose best-frame dHashes differ in at most `maxHamming` bits are near-duplicates; the higher score stays.
    /// Button clips are never dropped. Kept clips stay in their input order.
    public static func dedupe(_ clips: [ClipInfo], maxHamming: Int) -> [ClipInfo] {
        let ranked = clips.indices.sorted { a, b in
            let (x, y) = (clips[a], clips[b])
            if x.isButton != y.isButton { return x.isButton }
            let (sx, sy) = (x.score ?? -1, y.score ?? -1)
            if sx != sy { return sx > sy }
            return (x.fromMs, x.momentId) < (y.fromMs, y.momentId)
        }
        var keptHashes: [UInt64] = []
        var kept: Set<Int> = []
        for i in ranked {
            let hash = clips[i].bestFrameDhash
            if !clips[i].isButton, let hash, keptHashes.contains(where: { ($0 ^ hash).nonzeroBitCount <= maxHamming }) {
                continue
            }
            kept.insert(i)
            if let hash { keptHashes.append(hash) }
        }
        return clips.indices.filter(kept.contains).map { clips[$0] }
    }

    // MARK: Best sub-window

    /// The sharpest, steadiest `lengthS` window that still contains the trigger, from the sidecar's Stage 1 samples.
    /// Without samples it is centered on the trigger. Ties go to the window centered closest to the trigger.
    public static func bestWindow(_ clip: ClipInfo, lengthS: Double, config: EditConfig) -> (Double, Double) {
        let duration = clip.durationS
        guard lengthS < duration else { return (0, duration) }
        let latest = duration - lengthS
        let centered = min(max(clip.triggerS - lengthS / 2, 0), latest)
        guard !clip.samples.isEmpty else { return (centered, centered + lengthS) }

        let maxSharpness = max(clip.samples.map(\.sharpness).max() ?? 0, 1e-9)
        let maxChange = max(clip.samples.map(\.change).max() ?? 0, 1e-9)
        let quality = clip.samples.map { ($0.tS, $0.sharpness / maxSharpness - config.windowChangeWeight * $0.change / maxChange) }

        func score(_ start: Double) -> Double {
            let inside = quality.filter { start <= $0.0 && $0.0 <= start + lengthS }
            if !inside.isEmpty { return inside.map(\.1).reduce(0, +) / Double(inside.count) }
            let center = start + lengthS / 2
            return quality.min { abs($0.0 - center) < abs($1.0 - center) }!.1
        }

        let low = min(max(clip.triggerS - lengthS, 0), latest)
        let high = max(min(clip.triggerS, latest), low)
        var best = (start: centered, score: -Double.infinity, offset: Double.infinity)
        var start = low
        while start <= high + 1e-9 {
            let s = score(start)
            let offset = abs(start + lengthS / 2 - clip.triggerS)
            if s > best.score + 1e-9 || (abs(s - best.score) <= 1e-9 && offset < best.offset) {
                best = (start, s, offset)
            }
            start += config.windowStepS
        }
        return (best.start, best.start + lengthS)
    }

    // MARK: Thumbnails

    /// `config.thumbnailCount` JPEG frames evenly spaced through the proposed window, `thumbnailLongEdgePx` on the long edge.
    public static func thumbnails(for clip: ClipInfo, config: EditConfig) async throws -> [Data] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.clipURL))
        generator.appliesPreferredTrackTransform = true
        let edge = CGFloat(config.thumbnailLongEdgePx)
        generator.maximumSize = CGSize(width: edge, height: edge)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = config.thumbnailCount
        let span = clip.proposedOutS - clip.proposedInS
        var images: [Data] = []
        for k in 0..<count {
            let t = clip.proposedInS + (Double(k) + 0.5) * span / Double(count)
            let (image, _) = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600))
            if let jpeg = jpegData(image, quality: config.thumbnailJpegQuality) { images.append(jpeg) }
        }
        return images
    }

    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
