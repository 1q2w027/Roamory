import RoamoryKit
import UIKit

/// The globe's surface: an equirectangular map of the catalog's coarse continents on a dark ocean.
/// SCNSphere maps u = 0.5 to +z and grows eastward, which is `GeoMath`'s convention, so no offset is needed.
enum GlobeTexture {
    static let land = UIColor(red: 0x2e / 255, green: 0x4a / 255, blue: 0x3c / 255, alpha: 1)
    static let highlight = UIColor(red: 0x03 / 255, green: 0xfc / 255, blue: 0x73 / 255, alpha: 1)

    static func image(catalog: OnboardingCatalog, highlighted: String?,
                      size: CGSize = CGSize(width: 2048, height: 1024)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let ocean = CGGradient(colorsSpace: nil, colors: [
                UIColor(red: 0.10, green: 0.18, blue: 0.33, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.10, blue: 0.20, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.18, blue: 0.33, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 0.5, 1])!
            cg.drawLinearGradient(ocean, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // A faint graticule every 30°.
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.06).cgColor)
            cg.setLineWidth(2)
            for lon in stride(from: -180.0, through: 180, by: 30) {
                let x = point(GeoPoint(lat: 0, lon: lon), size).x
                cg.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height)])
            }
            for lat in stride(from: -60.0, through: 60, by: 30) {
                let y = point(GeoPoint(lat: lat, lon: 0), size).y
                cg.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)])
            }

            for continent in catalog.continents where continent.id != highlighted {
                fill(continent, color: land, in: cg, size: size)
            }
            if let lit = catalog.continents.first(where: { $0.id == highlighted }) {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: 40, color: highlight.withAlphaComponent(0.9).cgColor)
                fill(lit, color: highlight, in: cg, size: size)
                cg.restoreGState()
            }
        }
    }

    private static func fill(_ continent: Continent, color: UIColor, in cg: CGContext, size: CGSize) {
        cg.setFillColor(color.cgColor)
        cg.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
        cg.setLineWidth(6)
        cg.setLineJoin(.round)
        for outline in continent.outlines {
            guard let first = outline.first else { continue }
            let path = CGMutablePath()
            path.move(to: point(first, size))
            for p in outline.dropFirst() { path.addLine(to: point(p, size)) }
            path.closeSubpath()
            cg.addPath(path)
            cg.drawPath(using: .fillStroke)
        }
    }

    static func point(_ p: GeoPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (p.lon + 180) / 360 * size.width, y: (90 - p.lat) / 180 * size.height)
    }
}
