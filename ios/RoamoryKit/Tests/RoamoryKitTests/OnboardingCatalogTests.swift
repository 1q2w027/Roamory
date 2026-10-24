import XCTest
@testable import RoamoryKit

final class OnboardingCatalogTests: XCTestCase {
    private let catalog = try! OnboardingCatalog.bundled()

    func testBundledCatalogDecodes() {
        XCTAssertEqual(catalog.continents.count, 6)
        XCTAssertEqual(catalog.tripTypes.first?.id, "honeymoon")
        XCTAssertEqual(Set(catalog.tripTypes.map(\.id)).count, catalog.tripTypes.count)
    }

    func testEveryCityLiesInsideItsContinentOutline() {
        for continent in catalog.continents {
            for country in continent.countries {
                for city in country.cities {
                    XCTAssertTrue(continent.contains(city.location),
                                  "\(city.name) is outside \(continent.name)")
                }
            }
        }
    }

    func testDefaultDestinationIsInTheCatalog() {
        XCTAssertEqual(OnboardingCatalog.defaultCountry, "United States")
        let continent = catalog.continents.first { $0.name == OnboardingCatalog.defaultContinent }
        let country = continent?.countries.first { $0.name == OnboardingCatalog.defaultCountry }
        XCTAssertNotNil(country?.cities.first { $0.name == OnboardingCatalog.defaultCity })
    }

    func testContinentLookup() {
        XCTAssertEqual(catalog.continent(at: GeoPoint(lat: 35.01, lon: 135.77))?.id, "asia")
        XCTAssertEqual(catalog.continent(at: GeoPoint(lat: 48.86, lon: 2.35))?.id, "europe")
        XCTAssertEqual(catalog.continent(containing: "Japan")?.id, "asia")
    }

    func testContinentAtOceanIsNil() {
        XCTAssertNil(catalog.continent(at: GeoPoint(lat: 0, lon: -30)))
        XCTAssertNil(catalog.continent(at: GeoPoint(lat: -40, lon: -120)))
    }

    func testUnitVectorRoundTrip() {
        for p in [GeoPoint(lat: 35.01, lon: 135.77), GeoPoint(lat: -33.87, lon: 151.21),
                  GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 60, lon: -179)] {
            let back = GeoMath.geoPoint(GeoMath.unitVector(p))
            XCTAssertEqual(back.lat, p.lat, accuracy: 1e-9)
            XCTAssertEqual(back.lon, p.lon, accuracy: 1e-9)
        }
        let origin = GeoMath.unitVector(GeoPoint(lat: 0, lon: 0))
        XCTAssertEqual(origin.x, 0, accuracy: 1e-12)
        XCTAssertEqual(origin.y, 0, accuracy: 1e-12)
        XCTAssertEqual(origin.z, 1, accuracy: 1e-12)
    }
}
