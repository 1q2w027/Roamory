import Foundation

// Moment fields shared by the contracts (clip sidecar, agent request). Nullable fields are required keys,
// so encoders write an explicit null instead of leaving the key out.

public enum MomentSource: String, Codable, Sendable {
    case ai, button
    case localFallback = "local_fallback"
}

public enum EventType: String, Codable, Sendable {
    case scenery, landmark, activity, food, social, other
}

public struct Destination: Codable, Sendable, Equatable {
    public var country: String
    public var city: String?

    public init(country: String, city: String?) {
        self.country = country
        self.city = city
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(country, forKey: .country)
        try c.encode(city, forKey: .city)
    }
}
