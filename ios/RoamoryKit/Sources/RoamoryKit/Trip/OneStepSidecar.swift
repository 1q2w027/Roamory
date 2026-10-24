import Foundation

/// The sidecar for a clip saved in one step (TRD §5.5): the whole ring buffer, not the exact moment window.
public enum OneStepSidecar {
    /// - Parameters:
    ///   - savedAtMs: trip clock when the buffer was written out.
    ///   - prerollS: seconds of footage before `savedAtMs` that the file starts with (`RollingRecorder.start()`'s result).
    ///   - durationS: the finished file's length.
    public static func make(
        momentId: String, tripId: String, sessionId: String, source: MomentSource,
        triggerMs: Int, savedAtMs: Int, prerollS: Double, durationS: Double, hasAudio: Bool
    ) -> ClipSidecar {
        let fromMs = max(0, savedAtMs - Int(prerollS * 1000))
        return ClipSidecar(
            version: 1, momentId: momentId, tripId: tripId, sessionId: sessionId, source: source,
            triggerMs: triggerMs, fromMs: fromMs, toMs: fromMs + Int(durationS * 1000),
            clipPath: "clips/\(momentId).mp4", durationS: durationS, hasAudio: hasAudio,
            fpsProfile: [.init(tS: 0, fps: 30)], samples: []
        )
    }
}
