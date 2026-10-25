//
//  Transcriber.swift
//  Roamory
//

import AVFoundation
import Speech

/// Turns what the microphone hears into text on the iPhone (Apple's SpeechTranscriber; no audio leaves the phone), so
/// the director knows what was said. Each piece of speech keeps the recorder's time, so the director takes the words
/// up to its newest frame and, like the frames, only uses them up once it has answered.
nonisolated final class Transcriber: @unchecked Sendable {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Finalized speech, with its times on the capture clock in seconds.
    struct Segment {
        let start: Double
        let end: Double
        let text: String
    }

    /// Seconds of speech kept while the director does not take it, as long as the video buffer.
    private let retention: Double = 45

    /// Everything below is guarded by `lock`: `append` runs on the capture queue, the rest on the main actor.
    private let lock = NSLock()
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var segments: [Segment] = []
    /// Seconds of audio given to the analyzer so far, on its own timeline.
    private var fed: Double = 0
    /// Where the analyzer's timeline meets the capture clock, newest last; a new one starts after every gap in the
    /// audio (when filming pauses). The analyzer is not given the capture times itself: with `bufferStartTime` set it
    /// recognizes next to nothing.
    private var anchors: [(analyzer: Double, capture: Double)] = []
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?

    /// Picks the phone's language (English when it is not supported), downloads its model the first time and starts
    /// listening. Throws when this iPhone cannot transcribe; filming goes on without it.
    func start() async throws {
        guard SpeechTranscriber.isAvailable else { throw Failure(errorDescription: "Speech recognition is not available on this iPhone.") }
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale else { throw Failure(errorDescription: "No supported language for speech recognition.") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure(errorDescription: "No audio format for speech recognition.")
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: stream)
        let task = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self?.add(start: result.range.start.seconds, end: result.range.end.seconds, text: text)
                }
            } catch {}
        }
        lock.withLock {
            self.analyzer = analyzer
            self.input = continuation
            self.format = format
            self.resultsTask = task
        }
    }

    /// Stops listening for good.
    func stop() async {
        let (analyzer, input, task) = lock.withLock {
            defer {
                self.analyzer = nil; self.input = nil; self.resultsTask = nil; segments = []; fed = 0; anchors = []
            }
            return (self.analyzer, self.input, self.resultsTask)
        }
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        task?.cancel()
    }

    /// A microphone buffer. Call from the capture queue.
    func append(_ sample: CMSampleBuffer) {
        lock.withLock {
            guard let input, let format, let buffer = Self.pcm(of: sample) else { return }
            let converted: AVAudioPCMBuffer?
            if buffer.format == format {
                converted = buffer
            } else {
                if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: format) }
                converted = converter.flatMap { Self.convert(buffer, with: $0) }
            }
            guard let converted else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let expected = anchors.last.map { $0.capture + fed - $0.analyzer }
            if expected.map({ abs($0 - time) >= 0.1 }) ?? true { anchors.append((analyzer: fed, capture: time)) }
            fed += Double(converted.frameLength) / converted.format.sampleRate
            input.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// What was said up to `time` (the recorder's time of the newest frame) that the director has not taken yet, as
    /// one text; empty when nothing was said.
    func peek(through time: Double) -> String {
        lock.withLock { segments.filter { $0.start <= time }.map(\.text).joined(separator: " ") }
    }

    /// Uses up the speech up to `time`, once the director has answered. Speech still being recognized when the request
    /// went out arrives later and goes with the next one.
    func discard(through time: Double) {
        lock.withLock { segments.removeAll { $0.start <= time } }
    }

    /// Forgets what was heard, when the film stops and the buffer is emptied.
    func reset() {
        lock.withLock { segments = [] }
    }

    /// Speech the analyzer finalized, with its times on the analyzer's timeline.
    private func add(start: Double, end: Double, text: String) {
        lock.withLock {
            let anchor = anchors.last { $0.analyzer <= start } ?? anchors.first ?? (analyzer: 0, capture: 0)
            let offset = anchor.capture - anchor.analyzer
            let segment = Segment(start: start + offset, end: end + offset, text: text)
            segments.append(segment)
            segments.removeAll { $0.end < segment.end - retention }
        }
    }

    private static func pcm(of sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                  into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// The buffer in the converter's output format. The converter keeps its state between buffers, so resampling a
    /// stream of buffers leaves no gaps.
    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = .noDataNow
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}
