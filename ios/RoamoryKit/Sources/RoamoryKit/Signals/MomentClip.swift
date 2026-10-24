import Foundation

/// Links the trip clock (detection's milliseconds) to buffer time (capture presentation times, in seconds).
/// `originS` is the capture session's clock (host time) when detection started, which is trip ms 0.
public struct TripClock: Sendable {
    public let originS: Double

    public init(originS: Double) {
        self.originS = originS
    }

    public func bufferTime(atMs ms: Int) -> Double {
        originS + Double(ms) / 1000
    }

    /// Footage from before the trip started maps to 0.
    public func tripMs(atBufferTime t: Double) -> Int {
        max(0, Int(((t - originS) * 1000).rounded()))
    }
}

/// The footage a moment keeps (TRD 5.3 step 1): PRE_S before the trigger, never before the session started,
/// to POST_S after it. Trip clock.
public struct MomentWindow: Sendable, Equatable {
    public var fromMs: Int
    public var toMs: Int

    public init(fromMs: Int, toMs: Int) {
        self.fromMs = fromMs
        self.toMs = toMs
    }

    public init(triggerMs: Int, preS: Int, postS: Int, sessionStartMs: Int = 0) {
        self.init(fromMs: max(sessionStartMs, triggerMs - preS * 1000), toMs: triggerMs + postS * 1000)
    }
}

extension ClipSidecar {
    /// The sidecar for a clip saved from the buffer: `fromMs`/`toMs` are the trip-clock times of its first and last
    /// frame. One frame rate for the whole clip, and no Stage 1 samples (the pre-pass then centers on the trigger).
    public init(momentId: String, tripId: String, sessionId: String, source: MomentSource, triggerMs: Int,
                fromMs: Int, toMs: Int, hasAudio: Bool, fps: Double) {
        self.init(version: 1, momentId: momentId, tripId: tripId, sessionId: sessionId, source: source,
                  triggerMs: triggerMs, fromMs: fromMs, toMs: toMs, clipPath: "clips/\(momentId).mp4",
                  durationS: Double(toMs - fromMs) / 1000, hasAudio: hasAudio,
                  fpsProfile: [FpsStep(tS: 0, fps: fps)], samples: [])
    }
}
