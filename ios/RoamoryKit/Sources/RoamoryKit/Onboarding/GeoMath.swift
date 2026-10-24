import Foundation

/// Globe geometry shared by the destination globe's taps, pins and camera aim.
/// Unit sphere: latitude 0, longitude 0 is +z, the north pole is +y, and longitude 90° E is +x.
public enum GeoMath {
    /// Even-odd ray cast in (lon, lat). Outlines must not cross the antimeridian.
    public static func contains(_ polygon: [GeoPoint], _ p: GeoPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.lat > p.lat) != (b.lat > p.lat) {
                let t: Double = (p.lat - a.lat) / (b.lat - a.lat)
                let crossingLon: Double = a.lon + t * (b.lon - a.lon)
                if p.lon < crossingLon { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func unitVector(_ p: GeoPoint) -> SIMD3<Double> {
        let lat = p.lat * .pi / 180, lon = p.lon * .pi / 180
        return SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
    }

    /// The inverse of `unitVector`; `v` need not be normalized.
    public static func geoPoint(_ v: SIMD3<Double>) -> GeoPoint {
        let n = v / (v * v).sum().squareRoot()
        return GeoPoint(lat: asin(max(-1, min(1, n.y))) * 180 / .pi, lon: atan2(n.x, n.z) * 180 / .pi)
    }

    /// Great-circle angle between two points, in radians.
    public static func angle(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        acos(max(-1, min(1, (unitVector(a) * unitVector(b)).sum())))
    }

    /// The point midway between `points` on the sphere. `points` must not be empty.
    public static func center(of points: [GeoPoint]) -> GeoPoint {
        geoPoint(points.map(unitVector).reduce(.zero, +))
    }

    /// How far from the globe's center the camera must be, looking at `center`, for every point to sit within
    /// `fill` of half the `fieldOfView` (degrees), clamped to `range`. A cap too wide to fit gets the far end.
    public static func cameraDistance(fitting points: [GeoPoint], around center: GeoPoint, fieldOfView: Double,
                                      fill: Double, range: ClosedRange<Double>) -> Double {
        let theta = points.map { angle(center, $0) }.max() ?? 0
        let alpha = fill * fieldOfView / 2 * .pi / 180
        // A point θ from the point under the camera, seen from distance d, is atan(sin θ / (d − cos θ)) off axis.
        let d = cos(theta) + sin(theta) / tan(alpha)
        return min(max(d, range.lowerBound), range.upperBound)
    }
}
