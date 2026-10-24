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
}
