import Foundation

/// What the user sets up before recording (PRD onboarding, trimmed to what editing needs). Saved in UserDefaults.
public struct TripSettings: Codable, Sendable, Equatable {
    public var style: Style
    /// From the trip-type list, e.g. honeymoon, family, friends, school.
    public var tripType: String
    public var country: String
    public var city: String
    public var lengthDays: Int
    /// Off: no frame or plan request leaves the phone.
    public var allowCloudAnalysis: Bool

    public static let tripTypes = ["friends", "family", "honeymoon", "solo", "school"]

    public init(style: Style = .cinematic, tripType: String = "friends", country: String = "Japan", city: String = "Kyoto",
                lengthDays: Int = 1, allowCloudAnalysis: Bool = true) {
        self.style = style
        self.tripType = tripType
        self.country = country
        self.city = city
        self.lengthDays = lengthDays
        self.allowCloudAnalysis = allowCloudAnalysis
    }

    private static let key = "roamory.tripSettings"
    private static let installIdKey = "roamory.installId"

    public static func load(_ defaults: UserDefaults = .standard) -> TripSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TripSettings.self, from: $0) } ?? TripSettings()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// Random id made on first use, not a device identifier (contracts/evaluate_context.schema.json).
    public static func installId(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: installIdKey) { return id }
        let id = "i_\(UUID().uuidString.prefix(12).lowercased())"
        defaults.set(id, forKey: installIdKey)
        return id
    }

    /// The contracts need a country; a blank city is sent as null.
    var destination: (country: String, city: String?) {
        let country = country.trimmingCharacters(in: .whitespaces)
        let city = city.trimmingCharacters(in: .whitespaces)
        return (country.isEmpty ? TripSettings().country : country, city.isEmpty ? nil : city)
    }

    public func tripContext(tripId: String, startDate: Date = Date()) -> TripContext {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return TripContext(
            tripId: tripId, style: style, tripType: tripType,
            destination: Destination(country: destination.country, city: destination.city),
            startDate: formatter.string(from: startDate), allowCloudAnalysis: allowCloudAnalysis
        )
    }

    public func tripInfo(tripId: String, installId: String) -> TripInfo {
        TripInfo(tripId: tripId, installId: installId, style: style, tripType: tripType,
                 destination: .init(continent: nil, country: destination.country, city: destination.city),
                 lengthDays: max(lengthDays, 1))
    }
}
