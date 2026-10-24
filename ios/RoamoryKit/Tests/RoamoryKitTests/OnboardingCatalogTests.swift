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

    private func fit(_ points: [GeoPoint], around c: GeoPoint) -> Double {
        GeoMath.cameraDistance(fitting: points, around: c, fieldOfView: 38, fill: 0.9, range: 1.6...3.2)
    }

    func testFitAsiaZoomsOutToWorldView() {
        let asia = catalog.continents.first { $0.id == "asia" }!
        XCTAssertEqual(fit(asia.outlines.flatMap { $0 }, around: asia.center), 3.2, accuracy: 1e-9)
    }

    func testFitEuropeIsBetweenOldZoomAndWorld() {
        let europe = catalog.continents.first { $0.id == "europe" }!
        let d = fit(europe.outlines.flatMap { $0 }, around: europe.center)
        XCTAssertGreaterThan(d, 2.2)
        XCTAssertLessThan(d, 3.2)
        // Unclamped, so the farthest outline point sits exactly at fill × half the field of view.
        let theta = europe.outlines.flatMap { $0 }.map { GeoMath.angle(europe.center, $0) }.max()!
        XCTAssertEqual(atan(sin(theta) / (d - cos(theta))), 0.9 * 19 * .pi / 180, accuracy: 1e-9)
    }

    func testFitShowsFarApartCities() {
        let us = catalog.continents.flatMap(\.countries).first { $0.name == "United States" }!
        let sf = us.cities.first { $0.name == "San Francisco" }!.location
        XCTAssertGreaterThan(fit(us.cities.map(\.location), around: sf), 2.5)
    }

    func testFitSinglePointIsClosest() {
        let p = GeoPoint(lat: -33.87, lon: 151.21)
        XCTAssertEqual(fit([p], around: p), 1.6)
    }

    func testCenterAcrossAntimeridian() {
        let c = GeoMath.center(of: [GeoPoint(lat: 0, lon: 170), GeoPoint(lat: 0, lon: -170)])
        XCTAssertEqual(abs(c.lon), 180, accuracy: 1e-9)
        XCTAssertEqual(c.lat, 0, accuracy: 1e-9)
    }
}
