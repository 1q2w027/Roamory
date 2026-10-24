import Foundation

/// A place on the globe. Encoded as `[lat, lon]` to keep the catalog's outlines short.
public struct GeoPoint: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        lat = try c.decode(Double.self)
        lon = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(lat)
        try c.encode(lon)
    }
}

public struct City: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var location: GeoPoint
    public var id: String { name }
}

public struct Country: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var cities: [City]
    public var id: String { name }
}

public struct Continent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Where the globe turns to when the continent is chosen.
    public var center: GeoPoint
    /// Coarse coastlines, one polygon per landmass (mainland first, then islands).
    public var outlines: [[GeoPoint]]
    public var countries: [Country]

    public func contains(_ point: GeoPoint) -> Bool {
        outlines.contains { GeoMath.contains($0, point) }
    }
}

/// A kind of trip for the setup deck (PRD FR-003).
public struct TripType: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var emoji: String
    /// Two hex colors, top to bottom.
    public var colors: [String]
}

/// Destinations and trip types for onboarding (TRD §3.2), from `Resources/onboarding_catalog.json`.
public struct OnboardingCatalog: Codable, Sendable {
    public var continents: [Continent]
    public var tripTypes: [TripType]

    enum CodingKeys: String, CodingKey {
        case continents
        case tripTypes = "trip_types"
    }

    /// The destination onboarding starts at before the user has chosen one.
    public static let defaultContinent = "North America"
    public static let defaultCountry = "United States"
    public static let defaultCity = "New York"

    public static func bundled() throws -> OnboardingCatalog {
        try BundledResources.decode(OnboardingCatalog.self, named: "onboarding_catalog")
    }

    public func continent(at point: GeoPoint) -> Continent? {
        continents.first { $0.contains(point) }
    }

    public func continent(containing country: String) -> Continent? {
        continents.first { $0.countries.contains { $0.name == country } }
    }
}
