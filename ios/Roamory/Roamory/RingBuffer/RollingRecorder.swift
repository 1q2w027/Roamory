//
//  RollingRecorder.swift
//  Roamory
//

import AVFoundation

/// Keeps the last `retention` seconds of camera video (and audio) in memory as encoded samples.
/// `start()` saves the whole buffer to a file and keeps writing live samples to it; `stop()` closes the
/// file. The buffer keeps filling either way. Nothing reaches the disk unless `start()` is called.
nonisolated final class RollingRecorder: @unchecked Sendable {
    nonisolated struct Config {
        /// How much footage the buffer keeps, in seconds.
        var retention = 45.0
        var encoder = HEVCEncoder.Config()
        /// A pause in the video longer than this (seconds) means capture was interrupted, e.g. the app was in the background.
        var gapThreshold = 1.0
    }

    nonisolated enum RecorderError: LocalizedError {
        case bufferEmpty, alreadySaving, notSaving

        var errorDescription: String? {
            switch self {
            case .bufferEmpty: "Nothing in the buffer yet."
            case .alreadySaving: "Already saving."
            case .notSaving: "Not saving."
            }
        }
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
    private var videoFormat: CMFormatDescription?
    private var audioFormat: CMFormatDescription?
    private var writer: ClipWriter?
    /// Set while `stop()` waits for the keyframe that ends the clip.
    private var stopContinuation: CheckedContinuation<ClipWriter, Error>?
    private let stopTimeout: TimeInterval
    private let gapThreshold: TimeInterval
    private var encoder: HEVCEncoder!

    init(config: Config = Config()) {
        stopTimeout = config.encoder.keyframeInterval + 1
        gapThreshold = config.gapThreshold
        video = RingBuffer(retention: config.retention)
        audio = RingBuffer(retention: config.retention)
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
        encoder.encode(pixels, at: CMSampleBufferGetPresentationTimeStamp(sample))
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
                }
            }
        }
        return try await writer.finish()
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
