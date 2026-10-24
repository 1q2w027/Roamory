//
//  ClipWriter.swift
//  Roamary
//

import AVFoundation

/// Writes encoded video (and audio, as AAC) to an mp4 without re-encoding the video.
/// Every method must run on `queue`, which is also where the retries run.
nonisolated final class ClipWriter: @unchecked Sendable {
    let url: URL
    /// Set when the file can no longer be written.
    private(set) var failure: Error?

    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var pendingVideo: [CMSampleBuffer] = []
    private var pendingAudio: [CMSampleBuffer] = []
    private var finishContinuation: CheckedContinuation<URL, Error>?
    private var finishing = false
    private var retryScheduled = false

    /// The file starts at `start`, the presentation time of the first video sample.
    init(url: URL, videoFormat: CMFormatDescription, audioFormat: CMFormatDescription?,
         start: CMTime, queue: DispatchQueue) throws {
        self.url = url
        self.queue = queue
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        if let audioFormat, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat)?.pointee {
            let channels = Int(min(asbd.mChannelsPerFrame, 2))
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: asbd.mSampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 64_000 * channels,
            ], sourceFormatHint: audioFormat)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.startSession(atSourceTime: start)
    }

    func appendVideo(_ sample: CMSampleBuffer) {
        pendingVideo.append(sample)
        drain()
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        guard audioInput != nil else { return }
        pendingAudio.append(sample)
        drain()
    }

    /// Writes everything still queued, closes the file and returns its URL.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.finishContinuation = continuation
                self.finishing = true
                self.drain()
            }
        }
    }

    /// Abandons the file.
    func cancel() {
        pendingVideo = []
        pendingAudio = []
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    /// Hands the queued samples to the writer in time order for as long as it accepts them.
    /// When it is busy (the first call writes the whole buffer at once), tries again shortly.
    private func drain() {
        while failure == nil, let isVideo = nextIsVideo() {
            let input = isVideo ? videoInput : audioInput!
            guard input.isReadyForMoreMediaData else {
                scheduleRetry()
                return
            }
            let sample = isVideo ? pendingVideo.removeFirst() : pendingAudio.removeFirst()
            if !input.append(sample) {
                failure = writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        if failure == nil && finishing && pendingVideo.isEmpty && pendingAudio.isEmpty {
            finishing = false
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
            writer.finishWriting { [self] in
                let result: Result<URL, Error> = writer.status == .completed
                    ? .success(url) : .failure(writer.error ?? CocoaError(.fileWriteUnknown))
                finishContinuation?.resume(with: result)
                finishContinuation = nil
            }
        }
        if let failure {
            pendingVideo = []
            pendingAudio = []
            finishContinuation?.resume(throwing: failure)
            finishContinuation = nil
        }
    }

    /// Whether the earliest queued sample is video (true) or audio (false); nil when nothing is queued.
    private func nextIsVideo() -> Bool? {
        switch (pendingVideo.first, pendingAudio.first) {
        case (nil, nil): return nil
        case (_?, nil): return true
        case (nil, _?): return false
        case let (v?, a?):
            return CMSampleBufferGetPresentationTimeStamp(v) <= CMSampleBufferGetPresentationTimeStamp(a)
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 0.05) {
            self.retryScheduled = false
            self.drain()
        }
    }
}
