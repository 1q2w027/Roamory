import AVFoundation
import Foundation

/// Runs a finished recording through Stage 1 detection (TRD 6), in place of the live camera feed.
/// Used by the app after a recording stops, and by detector-replay on the Mac.
public enum FileDetection {
    public enum Error: Swift.Error, Equatable {
        case noVideoTrack
        case readFailed(String)
    }

    /// One Stage 1 sample, kept for the clip sidecars (`ClipSidecar.Sample`).
    public struct Sample: Sendable, Equatable {
        /// From the recording's start.
        public var tMs: Int
        public var sharpness: Double
        public var change: Double
        public var dhash: UInt64
    }

    /// Samples the video every `sample_interval_s` and feeds `detector`. Button presses go in at their time,
    /// before the first sample after them, as they would live.
    /// - Parameters:
    ///   - buttonPressesMs: times from the recording's start.
    ///   - waitForRequests: wait for cloud requests after each sample, so a fast read never outruns the queue.
    ///   - progress: 0…1 through the video.
    /// - Returns: every sample taken, oldest first. Detection is idle when this returns.
    @discardableResult
    public static func detect(
        video: URL, buttonPressesMs: [Int] = [], detector: MomentDetector, config: DetectionConfig,
        waitForRequests: Bool, progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Sample] {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Error.noVideoTrack }
        let durationMs = max(try await asset.load(.duration).seconds * 1000, 1)
        // iPhone recordings are stored sensor-side up with a rotation in the track; turn every frame upright.
        let orientation = FrameSampler.orientation(for: try await track.load(.preferredTransform))
        let size = try await track.load(.naturalSize)
        let portrait = orientation == .left || orientation == .right ? size.width > size.height : size.height > size.width
        let (lumaW, lumaH) = portrait ? (config.lumaHeight, config.lumaWidth) : (config.lumaWidth, config.lumaHeight)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        guard reader.startReading() else { throw Error.readFailed(reader.error?.localizedDescription ?? "cannot start") }

        var presses = buttonPressesMs.sorted()[...]
        let intervalMs = Int(config.sampleIntervalS * 1000)
        var nextMarkMs = 0
        var previous: LumaFrame?
        var samples: [Sample] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let tMs = Int(CMSampleBufferGetPresentationTimeStamp(buffer).seconds * 1000)
            guard tMs >= nextMarkMs, let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            nextMarkMs += intervalMs * ((tMs - nextMarkMs) / intervalMs + 1)
            while let press = presses.first, press < tMs {
                presses.removeFirst()
                _ = await detector.buttonPressed(atMs: press)
            }
            guard let jpeg = FrameSampler.jpeg(pixels, longEdge: config.jpegLongEdgePx, quality: config.jpegQuality,
                                               orientation: orientation) else { continue }
            let luma = FrameSampler.luma(pixels, width: lumaW, height: lumaH, orientation: orientation)
            let signals = FrameSignals.compute(luma, previous: previous)
            previous = luma
            samples.append(Sample(tMs: tMs, sharpness: signals.sharpness, change: signals.change, dhash: signals.dhash))
            await detector.ingest(SampledFrame(tMs: tMs, luma: luma, jpeg: jpeg, dwell: 0))
            if waitForRequests { await detector.waitForIdle() }
            progress?(min(Double(tMs) / durationMs, 1))
        }
        if reader.status == .failed { throw Error.readFailed(reader.error?.localizedDescription ?? "unknown") }
        for press in presses { _ = await detector.buttonPressed(atMs: press) }
        await detector.waitForIdle()
        progress?(1)
        return samples
    }
}
