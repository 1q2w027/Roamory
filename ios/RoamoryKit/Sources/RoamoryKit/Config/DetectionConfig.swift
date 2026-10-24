import Foundation

/// Stage 1 detection thresholds and settings from the bundled `detection_config.json` (TRD 6, 8.2, 8.3).
public struct DetectionConfig: Codable, Sendable, Equatable {
    /// Seconds between sampled frames.
    public var sampleIntervalS: Double
    /// Size of the grayscale copy the signals are computed on.
    public var lumaWidth: Int
    public var lumaHeight: Int
    public var jpegLongEdgePx: Int
    public var jpegQuality: Double
    public var framesPerRequest: Int
    /// Seconds a moment keeps before and after its trigger (TRD 5.3 `PRE_S`, `POST_S`).
    public var preS: Int
    public var postS: Int

    /// Local score L = weights · (change spike, dwell, quality, novelty).
    public var weightChangeSpike: Double
    public var weightDwell: Double
    public var weightQuality: Double
    public var weightNovelty: Double
    /// Samples averaged as the change baseline.
    public var changeWindow: Int
    /// Change above the baseline that counts as a full spike.
    public var changeSpikeScale: Double
    /// Laplacian variance that counts as fully sharp.
    public var sharpnessFull: Double
    /// dHash distance from recent escalations that counts as fully novel.
    public var noveltyFullBits: Int
    /// A frame below this quality (black, blown out, lens covered) is unusable and scores L = 0.
    public var minQuality: Double

    /// EMA weight of the newest L in the smoothed score.
    public var smoothingAlpha: Double
    /// Escalation threshold with a full bucket; it rises by `tauBudgetSlope` as the bucket drains.
    public var tauBase: Double
    public var tauBudgetSlope: Double
    public var cooldownS: Double
    public var minDhashDistance: Int
    /// Every Nth sample is evaluated regardless of score, so static scenery still gets a look.
    public var forcedEvery: Int
    public var bucketCapacity: Double
    public var bucketRefillS: Double
    /// With no cloud answer, keep a moment only if its L is at least this.
    public var localFallbackMin: Double

    public var evaluateTimeoutS: Double
    public var maxInFlight: Int
    public var maxQueued: Int
    public var demoCooldownS: Double
    public var demoTauBase: Double

    enum CodingKeys: String, CodingKey {
        case sampleIntervalS = "sample_interval_s"
        case lumaWidth = "luma_width"
        case lumaHeight = "luma_height"
        case jpegLongEdgePx = "jpeg_long_edge_px"
        case jpegQuality = "jpeg_quality"
        case framesPerRequest = "frames_per_request"
        case preS = "pre_s"
        case postS = "post_s"
        case weightChangeSpike = "weight_change_spike"
        case weightDwell = "weight_dwell"
        case weightQuality = "weight_quality"
        case weightNovelty = "weight_novelty"
        case changeWindow = "change_window"
        case changeSpikeScale = "change_spike_scale"
        case sharpnessFull = "sharpness_full"
        case noveltyFullBits = "novelty_full_bits"
        case minQuality = "min_quality"
        case smoothingAlpha = "smoothing_alpha"
        case tauBase = "tau_base"
        case tauBudgetSlope = "tau_budget_slope"
        case cooldownS = "cooldown_s"
        case minDhashDistance = "min_dhash_distance"
        case forcedEvery = "forced_every"
        case bucketCapacity = "bucket_capacity"
        case bucketRefillS = "bucket_refill_s"
        case localFallbackMin = "local_fallback_min"
        case evaluateTimeoutS = "evaluate_timeout_s"
        case maxInFlight = "max_in_flight"
        case maxQueued = "max_queued"
        case demoCooldownS = "demo_cooldown_s"
        case demoTauBase = "demo_tau_base"
    }

    public static func bundled() throws -> DetectionConfig {
        try BundledResources.decode(DetectionConfig.self, named: "detection_config")
    }
}
