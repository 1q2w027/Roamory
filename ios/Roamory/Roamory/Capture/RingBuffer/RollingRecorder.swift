//
//  RollingRecorder.swift
//  Roamory
//

import AVFoundation
import CoreImage
import ImageIO

/// Keeps the last `retention` seconds of camera video (and audio) in memory as encoded samples, plus a small
/// JPEG still taken at every keyframe, so a few frames can be sent off without decoding the video.
/// `start()` saves the whole buffer to a file and keeps writing live samples to it; `stop()` closes the
/// file. The buffer keeps filling either way. Nothing reaches the disk unless `start()` is called.
nonisolated final class RollingRecorder: @unchecked Sendable {
    nonisolated struct Config {
        /// How much footage the buffer keeps, in seconds.
        var retention = 45.0
        var encoder = HEVCEncoder.Config()
        /// Longest side, in pixels, and JPEG quality of the stills.
        var stillMaxSide: CGFloat = 768
        var stillQuality: CGFloat = 0.6
        /// A pause in the video longer than this (seconds) means capture was interrupted, e.g. the app was in the background.
        var gapThreshold = 1.0
    }

    nonisolated enum RecorderError: LocalizedError {
        case bufferEmpty, noNewFrames, alreadySaving, notSaving, footageGone

        var errorDescription: String? {
            switch self {
            case .bufferEmpty: "Nothing in the buffer yet."
            case .noNewFrames: "No new frames since the last Evaluate. Wait a couple of seconds."
            case .alreadySaving: "Already saving."
            case .notSaving: "Not saving."
            case .footageGone: "That footage is no longer in the buffer."
            }
        }
    }

    /// A file written by `writeClip`. `start` and `end` are the presentation times (seconds) of its first and last video sample.
    nonisolated struct SavedClip: Sendable {
        let url: URL
        let start: Double
        let end: Double
        let hasAudio: Bool
    }

    /// Called (on an arbitrary queue) with a problem that does not end a save, such as an encoder error.
    var onError: (@Sendable (Error) -> Void)?

    /// Called (on an arbitrary queue) when a save ends without `stop()`: the file so far when capture was
    /// interrupted, or the error when the file could not be written.
    var onSaveEnded: (@Sendable (Result<URL, Error>) -> Void)?

    /// Guards everything below except `encoder`, which only the capture queue touches.
    private let queue = DispatchQueue(label: "roamory.buffer")
    private var video: RingBuffer<CMSampleBuffer>
    private var audio: RingBuffer<CMSampleBuffer>
    /// A JPEG of the frame at each keyframe the recorder asked for, so about one per `keyframeInterval`.
    private var stills: RingBuffer<Data>
    private var videoFormat: CMFormatDescription?
    private var audioFormat: CMFormatDescription?
    private var writer: ClipWriter?
    /// Set while `stop()` waits for the keyframe that ends the clip.
    private var stopContinuation: CheckedContinuation<ClipWriter, Error>?
    private let stopTimeout: TimeInterval
    private let gapThreshold: TimeInterval
    private let stillInterval: TimeInterval
    private let stillMaxSide: CGFloat
    private let stillQuality: CGFloat
    private let ciContext = CIContext()
    /// Camera frame times, touched only on the capture queue (`handle(video:)`).
    private var lastFrameTime: Double?
    private var lastStillTime: Double?
    private var encoder: HEVCEncoder!

    init(config: Config = Config()) {
        stopTimeout = config.encoder.keyframeInterval + 1
        gapThreshold = config.gapThreshold
        stillInterval = config.encoder.keyframeInterval
        stillMaxSide = config.stillMaxSide
        stillQuality = config.stillQuality
        video = RingBuffer(retention: config.retention)
        audio = RingBuffer(retention: config.retention)
        stills = RingBuffer(retention: config.retention)
        encoder = HEVCEncoder(config: config.encoder) { [weak self] sample, isKeyframe in
            self?.queue.async { self?.ingest(video: sample, isKeyframe: isKeyframe) }
        } onError: { [weak self] message in
            self?.report(NSError(domain: "RollingRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }

    // MARK: Input from the camera

    /// A raw camera frame. Call from the capture queue.
    func handle(video sample: CMSampleBuffer) {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        captureStill(of: pixels, at: time.seconds)
        encoder.encode(pixels, at: time)
    }

    /// Every `stillInterval` seconds, makes this frame a keyframe and keeps a JPEG of it. The encoder only reports
    /// a keyframe after the picture has gone in, so the recorder decides which frames are keyframes itself.
    private func captureStill(of pixels: CVPixelBuffer, at time: Double) {
        // After a pause the old stills can't join the new ones, just like the video buffer.
        let paused = lastFrameTime.map { time - $0 > gapThreshold } ?? false
        lastFrameTime = time
        if paused { lastStillTime = nil }
        guard lastStillTime.map({ time - $0 >= stillInterval }) ?? true else { return }
        lastStillTime = time
        encoder.requestKeyframe()
        guard let jpeg = jpeg(of: pixels) else { return }
        queue.async {
            if paused { self.stills.removeAll() }
            self.stills.append(.init(time: time, isKeyframe: true, payload: jpeg))
        }
    }

    private func jpeg(of pixels: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixels)
        let scale = min(1, stillMaxSide / max(image.extent.width, image.extent.height))
        return ciContext.jpegRepresentation(
            of: image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: stillQuality])
    }

    /// A microphone buffer.
    func handle(audio sample: CMSampleBuffer) {
        queue.async { self.ingest(audio: sample) }
    }

    // MARK: Save control

    /// Starts saving: the whole buffer goes into a new mp4 now, and every sample after that is appended
    /// until `stop()`. Returns the seconds of footage from before the call that the file begins with.
    @discardableResult
    func start(to url: URL = RollingRecorder.temporaryClipURL()) async throws -> TimeInterval {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.beginSaving(to: url) })
            }
        }
    }

    /// Stops saving, finishes the file and returns it. The file runs on until the next keyframe (one is requested
    /// right away), so it ends on a whole group of pictures, and that keyframe becomes the first sample of the
    /// emptied buffer: the next `start()` only has footage from after this clip.
    func stop() async throws -> URL {
        let writer: ClipWriter = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.writer != nil, self.stopContinuation == nil else {
                    return continuation.resume(throwing: RecorderError.notSaving)
                }
                self.stopContinuation = continuation
                self.encoder.requestKeyframe()
                // No frames are coming (the camera stalled), so end the clip where it is.
                self.queue.asyncAfter(deadline: .now() + self.stopTimeout) {
                    guard self.stopContinuation != nil else { return }
                    self.endSaving()
                    self.video.removeAll()
                    self.audio.removeAll()
                    self.stills.removeAll()
                }
            }
        }
        return try await writer.finish()
    }

    /// Writes the buffered footage from the keyframe at or before `start` up to `end` (both presentation times in
    /// seconds) to a new mp4, and returns once the file is finished. An `end` past the newest sample writes up to it.
    /// The buffer and a save started with `start()` are untouched.
    func writeClip(from start: Double, to end: Double, url: URL) async throws -> SavedClip {
        let (writer, clip): (ClipWriter, SavedClip) = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    let videoSnapshot = self.video.range(from: start, to: end)
                    guard let first = videoSnapshot.first, let last = videoSnapshot.last, let videoFormat = self.videoFormat else {
                        throw RecorderError.footageGone
                    }
                    let audioSnapshot = self.audio.range(from: first.time, to: end)
                    let writer = try ClipWriter(url: url, videoFormat: videoFormat, audioFormat: self.audioFormat,
                                                start: CMSampleBufferGetPresentationTimeStamp(first.payload), queue: self.queue)
                    for entry in videoSnapshot { writer.appendVideo(entry.payload) }
                    for entry in audioSnapshot { writer.appendAudio(entry.payload) }
                    let hasAudio = self.audioFormat != nil && !audioSnapshot.isEmpty
                    return (writer, SavedClip(url: url, start: first.time, end: last.time, hasAudio: hasAudio))
                })
            }
        }
        do {
            _ = try await writer.finish()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return clip
    }

    /// Up to `count` of the stills recorded since the last `discardFrames`, as JPEGs spread evenly over them, oldest first.
    /// `through` is the time of the newest still looked at; pass it to `discardFrames` once the frames have been used.
    func peekFrames(count: Int) throws -> (frames: [Data], through: Double) {
        let (all, through) = queue.sync { (stills.entries.map(\.payload), stills.last?.time) }
        guard let through, !all.isEmpty else { throw RecorderError.noNewFrames }
        guard count < all.count else { return (all, through) }
        guard count > 1 else { return ([all[all.count - 1]], through) }
        return ((0..<count).map { all[$0 * (all.count - 1) / (count - 1)] }, through)
    }

    /// Drops the stills up to and including `through`, so the next `peekFrames` only sees newer ones.
    /// The video buffer is untouched.
    func discardFrames(through: Double) {
        queue.async { self.stills.removeAll(before: through.nextUp) }
    }

    var isSaving: Bool { queue.sync { writer != nil } }

    /// Seconds of video currently held.
    var bufferedDuration: TimeInterval { queue.sync { video.duration } }

    static func temporaryClipURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }

    // MARK: Queue-confined

    private func beginSaving(to url: URL) throws -> TimeInterval {
        guard writer == nil else { throw RecorderError.alreadySaving }
        // The buffer starts on a keyframe, so the file can be decoded from its first sample.
        let videoSnapshot = video.entries
        guard let first = videoSnapshot.first, let videoFormat else { throw RecorderError.bufferEmpty }
        let start = first.time
        let writer = try ClipWriter(url: url, videoFormat: videoFormat, audioFormat: audioFormat,
                                    start: CMSampleBufferGetPresentationTimeStamp(first.payload), queue: queue)
        for entry in videoSnapshot { writer.appendVideo(entry.payload) }
        for entry in audio.range(from: start) { writer.appendAudio(entry.payload) }
        self.writer = writer
        checkWriter()
        return video.duration
    }

    /// Hands the file to the waiting `stop()`.
    private func endSaving() {
        guard let continuation = stopContinuation, let writer else { return }
        stopContinuation = nil
        self.writer = nil
        continuation.resume(returning: writer)
    }

    /// The video skipped ahead. What was buffered before can't join what comes next, so the buffer starts over,
    /// and a save in progress ends at the last frame it has instead of freezing on it for the length of the gap.
    private func captureInterrupted() {
        if stopContinuation != nil {
            endSaving()
        } else if let writer {
            self.writer = nil
            Task {
                do { onSaveEnded?(.success(try await writer.finish())) } catch { onSaveEnded?(.failure(error)) }
            }
        }
        video.removeAll()
        audio.removeAll()
        encoder.requestKeyframe()
    }

    private func ingest(video sample: CMSampleBuffer, isKeyframe: Bool) {
        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if let last = video.last, time - last.time > gapThreshold {
            captureInterrupted()
        }
        if stopContinuation != nil && isKeyframe {
            // The clip ends just before this keyframe, which starts the next buffer.
            endSaving()
            video.removeAll()
            audio.trim(before: time)
            // Stills taken before this keyframe belong to the clip just ended.
            stills.removeAll(before: time)
        }
        videoFormat = CMSampleBufferGetFormatDescription(sample)
        video.append(.init(time: time, isKeyframe: isKeyframe, payload: sample))
        writer?.appendVideo(sample)
        checkWriter()
    }

    private func ingest(audio sample: CMSampleBuffer) {
        audioFormat = CMSampleBufferGetFormatDescription(sample)
        audio.append(.init(time: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                           isKeyframe: true, payload: sample))
        writer?.appendAudio(sample)
        checkWriter()
    }

    private func checkWriter() {
        guard let failure = writer?.failure else { return }
        writer?.cancel()
        writer = nil
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume(throwing: failure)
        } else {
            onSaveEnded?(.failure(failure))
        }
    }

    private func report(_ error: Error) {
        onError?(error)
    }
}
