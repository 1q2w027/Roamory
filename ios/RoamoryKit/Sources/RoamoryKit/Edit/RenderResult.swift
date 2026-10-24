import AVFoundation

public enum RenderError: Error, Equatable, Sendable {
    case missingClip(momentId: String)
    case cannotExport(String)
    case notPlayable
    case durationMismatch(expectedS: Double, actualS: Double)
}

/// The finished video file.
public struct RenderResult: Sendable {
    public var url: URL
    public var durationS: Double
    /// Wall-clock time from the first upload to the checked download.
    public var elapsedS: Double
    /// The video's size and frame rate.
    public var output: OutputFormat

    public init(url: URL, durationS: Double, elapsedS: Double, output: OutputFormat) {
        self.url = url
        self.durationS = durationS
        self.elapsedS = elapsedS
        self.output = output
    }

    /// "Video ready" only once the file loads, plays and has about the expected length (TRD 10). Returns its duration.
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
