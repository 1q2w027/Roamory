import AVFoundation
import os

public enum RenderError: Error, Equatable, Sendable {
    case missingClip(momentId: String)
    case noVideoTrack(momentId: String)
    case missingAsset(String)
    case transitionsTooLong(momentId: String)
    case cannotExport(String)
    case notPlayable
    case durationMismatch(expectedS: Double, actualS: Double)
    /// Debug only: `Renderer.simulateTransitionFailure`.
    case simulatedFailure
}

public struct RenderResult: Sendable {
    public var url: URL
    public var durationS: Double
    /// Wall-clock render time (performance target: under 2 minutes).
    public var elapsedS: Double
    /// The spec actually rendered: the input, or its hard-cut copy after a failed export with transitions.
    public var spec: EditSpec
    public var usedHardCutRetry: Bool
}

/// Renders an edit spec to an H.264 MP4 with AVFoundation, on the phone: the backup when Roamory Studio is not available.
public struct Renderer: Sendable {
    public var config: EditConfig
    /// Debug: fail the first export when it has transitions, to exercise the hard-cut retry.
    public var simulateTransitionFailure = false

    static let log = Logger(subsystem: "app.roamory", category: "render")

    public init(config: EditConfig) {
        self.config = config
    }

    /// - Parameters:
    ///   - clipURLs: the clip file for each `moment_id` in the spec.
    ///   - progress: export progress, 0...1.
    public func render(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> RenderResult {
        let clock = ContinuousClock()
        let start = clock.now
        let hasTransitions = spec.clips.contains { $0.transitionIn != .cut }
        var rendered = spec
        let duration: Double
        do {
            if simulateTransitionFailure && hasTransitions { throw RenderError.simulatedFailure }
            duration = try await renderOnce(spec, clipURLs: clipURLs, to: outputURL, progress: progress)
        } catch where hasTransitions && !(error is CancellationError) {
            // If rendering with transitions fails, retry once with hard cuts.
            Self.log.error("Render with transitions failed, retrying with hard cuts: \(String(describing: error))")
            rendered = spec.withHardCuts()
            progress(0)
            duration = try await renderOnce(rendered, clipURLs: clipURLs, to: outputURL, progress: progress)
        }
        let elapsed = (clock.now - start) / .seconds(1)
        Self.log.info("Rendered \(rendered.style.rawValue) \(rendered.clips.count) clips, \(duration)s video in \(elapsed)s")
        return RenderResult(
            url: outputURL, durationS: duration, elapsedS: elapsed, spec: rendered, usedHardCutRetry: rendered != spec
        )
    }

    /// Exports and checks the file; returns its duration.
    private func renderOnce(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Double {
        let built = try await CompositionBuilder.build(spec, clipURLs: clipURLs)
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: built.composition, presetName: config.exportPreset) else {
            throw RenderError.cannotExport("no export session for preset \(config.exportPreset)")
        }
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        session.shouldOptimizeForNetworkUse = true

        let states = session.states(updateInterval: 0.25)
        let observer = Task {
            for await state in states {
                if case let .exporting(p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { observer.cancel() }
        try await session.export(to: outputURL, as: .mp4)
        progress(1)
        return try await Self.verify(outputURL, expectedS: EditTimeline.totalDurationS(spec), toleranceS: config.renderDurationToleranceS)
    }

    /// "Video ready" only once the file loads, plays and has about the planned length. Returns its duration.
    static func verify(_ url: URL, expectedS: Double, toleranceS: Double) async throws -> Double {
        let (playable, duration) = try await AVURLAsset(url: url).load(.isPlayable, .duration)
        guard playable else { throw RenderError.notPlayable }
        let seconds = duration.seconds
        guard abs(seconds - expectedS) <= toleranceS else {
            throw RenderError.durationMismatch(expectedS: expectedS, actualS: seconds)
        }
        return seconds
    }
}

/// Builds the composition, video composition and audio mix for one spec.
enum CompositionBuilder {
    static let timescale: CMTimeScale = 600

    struct Built {
        var composition: AVMutableComposition
        var videoComposition: AVVideoComposition
        var audioMix: AVAudioMix?
    }

    /// One clip as placed on the composition timeline.
    private struct Placed {
        var track: AVMutableCompositionTrack
        var range: CMTimeRange
        var transform: CGAffineTransform
        /// Overlap with the previous clip (zero for the first clip and cuts).
        var overlapIn: CMTime
        var transition: Transition
        var transitionS: CMTime
        var caption: String?
    }

    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: timescale) }

    static func build(_ spec: EditSpec, clipURLs: [String: URL]) async throws -> Built {
        let composition = AVMutableComposition()
        let renderSize = CGSize(width: spec.output.width, height: spec.output.height)
        // Overlapping transitions need two alternating tracks (A/B); hard cuts need one.
        let trackCount = spec.clips.indices.contains { EditTimeline.overlapS(spec.clips, at: $0) > 0 } ? 2 : 1
        let keepOriginalAudio = !spec.music.duckOriginalAudio
        let videoTracks = try (0..<trackCount).map { _ in try addTrack(composition, .video) }
        let audioTracks = keepOriginalAudio ? try (0..<trackCount).map { _ in try addTrack(composition, .audio) } : []

        var placed: [Placed] = []
        var cursor = CMTime.zero
        for (i, clip) in spec.clips.enumerated() {
            guard let url = clipURLs[clip.momentId] else { throw RenderError.missingClip(momentId: clip.momentId) }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw RenderError.noVideoTrack(momentId: clip.momentId)
            }
            let (preferred, natural, sourceRange) = try await source.load(.preferredTransform, .naturalSize, .timeRange)

            let overlap = time(EditTimeline.overlapS(spec.clips, at: i))
            let start = CMTimeMaximum(.zero, cursor - overlap)
            let k = i % trackCount
            let wanted = CMTimeRange(start: time(clip.inS), end: time(clip.outS))
            let trim = wanted.intersection(sourceRange)
            guard trackEnd(videoTracks[k]) <= start else { throw RenderError.transitionsTooLong(momentId: clip.momentId) }
            try insert(trim, of: source, into: videoTracks[k], at: start)
            var scaled = [videoTracks[k]]

            // Original audio is skipped when ducked or when the clip has none (audio is off by default).
            if keepOriginalAudio, let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioTrim = trim.intersection(try await audio.load(.timeRange))
                if !audioTrim.isEmpty {
                    try insert(audioTrim, of: audio, into: audioTracks[k], at: start)
                    scaled.append(audioTracks[k])
                }
            }

            var duration = trim.duration
            if let ramp = clip.speedRamp {
                duration = applyRamp(ramp, to: scaled, at: start, sourceDuration: duration)
            }
            placed.append(Placed(
                track: videoTracks[k], range: CMTimeRange(start: start, duration: duration),
                transform: aspectFill(preferred: preferred, natural: natural, into: renderSize),
                overlapIn: overlap, transition: clip.transitionIn, transitionS: time(clip.transitionS), caption: clip.caption
            ))
            cursor = start + duration
        }

        // End card: a hard cut to the bundled black clip, stretched to the card's length.
        let endCardRange = CMTimeRange(start: cursor, duration: time(spec.endCard.durationS))
        guard let blackURL = BundledResources.blackClipURL(portrait: spec.output.isPortrait) else {
            throw RenderError.missingAsset("black end-card clip")
        }
        // Keep the asset itself alive: a track doesn't retain its asset, and inserting from a freed one fails.
        let blackAsset = AVURLAsset(url: blackURL)
        guard let black = try await blackAsset.loadTracks(withMediaType: .video).first else {
            throw RenderError.missingAsset("black end-card clip")
        }
        let (blackPreferred, blackNatural, blackRange) = try await black.load(.preferredTransform, .naturalSize, .timeRange)
        let endTrack = placed.last?.track ?? videoTracks[0]
        try insert(blackRange, of: black, into: endTrack, at: cursor)
        endTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: blackRange.duration), toDuration: endCardRange.duration)
        let total = endCardRange.end

        let instructions = videoInstructions(
            placed, endCard: (endTrack, endCardRange, aspectFill(preferred: blackPreferred, natural: blackNatural, into: renderSize))
        )
        let audioMix = try await musicAndMix(spec, composition: composition, originalTracks: audioTracks, placed: placed, total: total)

        // Captions show while their clip plays alone, clear of the transitions.
        let captions = placed.indices.compactMap { i -> TitleOverlay.Caption? in
            guard let text = placed[i].caption else { return nil }
            let overlapOut = i + 1 < placed.count ? placed[i + 1].overlapIn : .zero
            return TitleOverlay.Caption(
                text: text, startS: (placed[i].range.start + placed[i].overlapIn).seconds, endS: (placed[i].range.end - overlapOut).seconds
            )
        }
        let tool = TitleOverlay.animationTool(
            title: spec.title, captions: captions, endCard: spec.endCard, endCardStartS: cursor.seconds, renderSize: renderSize
        )
        let videoComposition = AVVideoComposition(configuration: .init(
            animationTool: tool,
            // A fixed output rate also smooths low-fps footage.
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(spec.output.fps)),
            instructions: instructions,
            renderSize: renderSize
        ))
        return Built(composition: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    // MARK: Tracks

    private static func addTrack(_ composition: AVMutableComposition, _ type: AVMediaType) throws -> AVMutableCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RenderError.cannotExport("could not add a \(type.rawValue) track")
        }
        return track
    }

    private static func trackEnd(_ track: AVMutableCompositionTrack) -> CMTime {
        track.segments.last?.timeMapping.target.end ?? .zero
    }

    /// Inserts `range` of `source` at `at`, padding the track with empty time first if needed.
    private static func insert(_ range: CMTimeRange, of source: AVAssetTrack, into track: AVMutableCompositionTrack, at: CMTime) throws {
        let end = trackEnd(track)
        if end < at { track.insertEmptyTimeRange(CMTimeRange(start: end, end: at)) }
        try track.insertTimeRange(range, of: source, at: at)
    }

    /// `scaleTimeRange` is a constant rate, so the ramp is 4 equal source steps.
    /// Returns the clip's new duration on the timeline.
    private static func applyRamp(
        _ ramp: EditSpec.SpeedRamp, to tracks: [AVMutableCompositionTrack], at start: CMTime, sourceDuration: CMTime
    ) -> CMTime {
        let step = time(ramp.overS / 4)
        var position = start
        for rate in ramp.stepRates {
            let scaled = time(ramp.overS / 4 / rate)
            for track in tracks {
                track.scaleTimeRange(CMTimeRange(start: position, duration: step), toDuration: scaled)
            }
            position = position + scaled
        }
        return position - start + (sourceDuration - CMTimeMultiply(step, multiplier: 4))
    }

    /// Rotates by the track's preferred transform, then scales to fill `size` and centers (aspect fill).
    static func aspectFill(preferred: CGAffineTransform, natural: CGSize, into size: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: natural).applying(preferred)
        let oriented = preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let scale = max(size.width / rect.width, size.height / rect.height)
        return oriented
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (size.width - rect.width * scale) / 2, y: (size.height - rect.height * scale) / 2))
    }

    // MARK: Video instructions

    /// Instructions that tile the timeline: each clip alone, then each overlap with both tracks.
    /// Dissolve cross-fades; fade dips through black. A first clip with a transition fades in from black.
    private static func videoInstructions(
        _ placed: [Placed], endCard: (track: AVMutableCompositionTrack, range: CMTimeRange, transform: CGAffineTransform)
    ) -> [AVVideoCompositionInstruction] {
        var instructions: [AVVideoCompositionInstruction] = []
        func add(_ range: CMTimeRange, _ layers: [AVVideoCompositionLayerInstruction.Configuration]) {
            guard range.duration > .zero else { return }
            instructions.append(AVVideoCompositionInstruction(configuration: .init(
                backgroundColor: CGColor(gray: 0, alpha: 1),
                layerInstructions: layers.map { AVVideoCompositionLayerInstruction(configuration: $0) },
                timeRange: range
            )))
        }
        func layer(_ p: Placed, at time: CMTime) -> AVVideoCompositionLayerInstruction.Configuration {
            var layer = AVVideoCompositionLayerInstruction.Configuration(trackID: p.track.trackID)
            layer.setTransform(p.transform, at: time)
            return layer
        }

        for (i, p) in placed.enumerated() {
            let overlapOut = i + 1 < placed.count ? placed[i + 1].overlapIn : .zero
            let solo = CMTimeRange(start: p.range.start + p.overlapIn, end: p.range.end - overlapOut)
            var only = layer(p, at: solo.start)
            if i == 0 && p.transition != .cut && p.transitionS > .zero {
                only.addOpacityRamp(.init(timeRange: CMTimeRange(start: .zero, duration: p.transitionS), start: 0, end: 1))
            }
            add(solo, [only])

            guard overlapOut > .zero else { continue }
            let next = placed[i + 1]
            let overlap = CMTimeRange(start: next.range.start, end: p.range.end)
            var outgoing = layer(p, at: overlap.start)
            var incoming = layer(next, at: overlap.start)
            if next.transition == .fade {
                let half = CMTimeMultiplyByRatio(overlap.duration, multiplier: 1, divisor: 2)
                outgoing.addOpacityRamp(.init(timeRange: CMTimeRange(start: overlap.start, duration: half), start: 1, end: 0))
                incoming.setOpacity(0, at: overlap.start)
                incoming.addOpacityRamp(.init(timeRange: CMTimeRange(start: overlap.start + half, end: overlap.end), start: 0, end: 1))
            } else {
                outgoing.addOpacityRamp(.init(timeRange: overlap, start: 1, end: 0))
            }
            // The first layer is on top.
            add(overlap, [outgoing, incoming])
        }

        var card = AVVideoCompositionLayerInstruction.Configuration(trackID: endCard.track.trackID)
        card.setTransform(endCard.transform, at: endCard.range.start)
        add(endCard.range, [card])
        return instructions
    }

    // MARK: Audio

    /// Loops the bundled music bed under the whole video at `gain_db`, and ramps original audio across overlaps.
    private static func musicAndMix(
        _ spec: EditSpec, composition: AVMutableComposition, originalTracks: [AVMutableCompositionTrack], placed: [Placed], total: CMTime
    ) async throws -> AVAudioMix? {
        var parameters: [AVAudioMixInputParameters] = []

        let musicAsset = BundledResources.musicURL(track: spec.music.track).map { AVURLAsset(url: $0) }
        if let musicAsset, let music = try await musicAsset.loadTracks(withMediaType: .audio).first {
            let musicRange = try await music.load(.timeRange)
            let track = try addTrack(composition, .audio)
            var at = CMTime.zero
            while musicRange.duration > .zero && at < total {
                let length = CMTimeMinimum(musicRange.duration, total - at)
                try track.insertTimeRange(CMTimeRange(start: musicRange.start, duration: length), of: music, at: at)
                at = at + length
            }
            let gain = Float(pow(10, spec.music.gainDb / 20))
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(gain, at: .zero)
            let fade = CMTimeMinimum(time(1.5), total)
            p.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0, timeRange: CMTimeRange(start: total - fade, duration: fade))
            parameters.append(p)
        } else {
            Renderer.log.error("No bundled music for track \(spec.music.track); rendering without music")
        }

        // Clip i's audio is on originalTracks[i % count], like its video.
        for (k, track) in originalTracks.enumerated() where !track.segments.isEmpty {
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(1, at: .zero)
            for (i, clip) in placed.enumerated() where i % originalTracks.count == k {
                let overlapOut = i + 1 < placed.count ? placed[i + 1].overlapIn : .zero
                if clip.overlapIn > .zero {
                    p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: clip.range.start, duration: clip.overlapIn))
                }
                if overlapOut > .zero {
                    p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: clip.range.end - overlapOut, end: clip.range.end))
                }
            }
            parameters.append(p)
        }

        guard !parameters.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}
