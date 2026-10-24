import Foundation

/// Codable mirror of contracts/render_request.schema.json: the `request` part of `POST /v1/render`.
public struct RenderRequest: Codable, Sendable, Equatable {
    public struct Context: Codable, Sendable, Equatable {
        public var destination: Destination
        public var tripType: String
        public var startDate: String

        public init(destination: Destination, tripType: String, startDate: String) {
            self.destination = destination
            self.tripType = tripType
            self.startDate = startDate
        }

        public init(trip: TripContext) {
            self.init(destination: trip.destination, tripType: trip.tripType, startDate: trip.startDate)
        }

        enum CodingKeys: String, CodingKey {
            case destination
            case tripType = "trip_type"
            case startDate = "start_date"
        }
    }

    /// One uploaded trimmed file.
    public struct Clip: Codable, Sendable, Equatable {
        public var momentId: String
        public var durationS: Double
        public var hasAudio: Bool

        public init(momentId: String, durationS: Double, hasAudio: Bool) {
            self.momentId = momentId
            self.durationS = durationS
            self.hasAudio = hasAudio
        }

        enum CodingKeys: String, CodingKey {
            case momentId = "moment_id"
            case durationS = "duration_s"
            case hasAudio = "has_audio"
        }
    }

    /// Rebased onto the uploaded files (`ClipTrimmer.rebased`).
    public var editSpec: EditSpec
    public var context: Context
    public var clips: [Clip]

    public init(editSpec: EditSpec, context: Context, clips: [Clip]) {
        self.editSpec = editSpec
        self.context = context
        self.clips = clips
    }

    enum CodingKeys: String, CodingKey {
        case editSpec = "edit_spec"
        case context, clips
    }
}

/// Codable mirror of contracts/render_job.schema.json: the body of `GET /v1/render/{job_id}`.
public struct RenderJob: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case queued, rendering, completed, failed
    }

    public var jobId: String
    public var status: Status
    public var progress: Double
    public var error: APIError?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, progress, error
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jobId, forKey: .jobId)
        try c.encode(status, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encode(error, forKey: .error)
    }
}
