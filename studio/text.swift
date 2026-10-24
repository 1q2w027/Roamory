// roamory-text: draws text layers (any installed font, colour, outline, shadow, box) and simple shapes into PNGs with
// a transparent background, because Homebrew's ffmpeg has no drawtext. Claude lays them over footage with overlay.
// Usage: roamory-text <spec.json>   or   roamory-text --fonts   (spec format in studio/prompt.md)
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("roamory-text: \(message)\n".data(using: .utf8)!)
    exit(2)
}

func safePath(_ path: String) -> String {
    if path.hasPrefix("/") || path.split(separator: "/").contains("..") { fail("\(path): use a path inside the workspace") }
    return path
}

let args = CommandLine.arguments
if args.count == 2 && args[1] == "--fonts" {
    print(NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.joined(separator: "\n"))
    exit(0)
}
guard args.count == 2 else { fail("usage: roamory-text <spec.json> | --fonts") }
let specPath = safePath(args[1])
guard let data = FileManager.default.contents(atPath: specPath),
      let spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { fail("\(specPath) is not a JSON object") }

func num(_ v: Any?) -> CGFloat? { (v as? NSNumber).map { CGFloat($0.doubleValue) } }

// "#RRGGBB" or "#RRGGBBAA".
func color(_ v: Any?, _ fallback: NSColor) -> NSColor {
    guard var s = v as? String else { return fallback }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8, let x = UInt64(s, radix: 16) else { fail("bad colour \(v!)") }
    let rgba = s.count == 6 ? x << 8 | 0xFF : x
    return NSColor(srgbRed: CGFloat(rgba >> 24 & 0xFF) / 255, green: CGFloat(rgba >> 16 & 0xFF) / 255,
                   blue: CGFloat(rgba >> 8 & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
}

let weights: [String: (NSFont.Weight, Int)] = [
    "ultralight": (.ultraLight, 2), "thin": (.thin, 3), "light": (.light, 4), "regular": (.regular, 5),
    "medium": (.medium, 6), "semibold": (.semibold, 8), "bold": (.bold, 9), "heavy": (.heavy, 11), "black": (.black, 12),
]

// A family ("Avenir Next", "Didot"), a PostScript name ("Futura-Bold"), or system, rounded, serif, mono.
func font(_ layer: [String: Any], _ points: CGFloat) -> NSFont {
    let (weight, managerWeight) = weights[layer["weight"] as? String ?? "regular"] ?? (.regular, 5)
    let italic = layer["italic"] as? Bool ?? false
    let name = layer["font"] as? String ?? "system"
    var f: NSFont
    let designs: [String: NSFontDescriptor.SystemDesign] = ["rounded": .rounded, "serif": .serif, "mono": .monospaced]
    if name == "system" || designs[name] != nil {
        f = NSFont.systemFont(ofSize: points, weight: weight)
        if let design = designs[name], let d = f.fontDescriptor.withDesign(design) { f = NSFont(descriptor: d, size: points) ?? f }
    } else if let family = NSFontManager.shared.font(withFamily: name, traits: italic ? .italicFontMask : [],
                                                      weight: managerWeight, size: points) {
        return family
    } else if let named = NSFont(name: name, size: points) {
        f = named
    } else {
        fail("no font \(name); run roamory-text --fonts")
    }
    return italic ? NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) : f
}

func image(_ spec: [String: Any], defaults: [String: Any]) {
    let merged = defaults.merging(spec) { $1 }
    guard let out = merged["out"] as? String else { fail("every image needs out") }
    guard let width = num(merged["width"]).map(Int.init), let height = num(merged["height"]).map(Int.init),
          width > 0, height > 0, width <= 8192, height <= 8192 else { fail("\(out): needs width and height") }
    let W = CGFloat(width), H = CGFloat(height), short = min(W, H)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { fail("\(out): cannot make the bitmap") }
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    color(merged["background"], .clear).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill(using: .copy)

    for (k, layer) in (merged["layers"] as? [[String: Any]] ?? []).enumerated() {
        // Positions and sizes are fractions: x of the width, y of the height from the top, sizes of the short side.
        let x = (num(layer["x"]) ?? 0.5) * W, y = H - (num(layer["y"]) ?? 0.5) * H
        let rotation = num(layer["rotation"]) ?? 0
        let opacity = num(layer["opacity"]) ?? 1
        context.saveGraphicsState()
        context.cgContext.setAlpha(opacity)
        let move = NSAffineTransform()
        move.translateX(by: x, yBy: y)
        move.rotate(byDegrees: -rotation)
        move.concat()
        if layer["text"] == nil {
            // A shape: rect (w, h, radius) or ellipse, filled and/or stroked; anchored at its centre.
            let w = (num(layer["w"]) ?? 0.1) * W, h = (num(layer["h"]) ?? 0.1) * H
            let rect = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let radius = (num(layer["radius"]) ?? 0) * short
            let path = layer["shape"] as? String == "ellipse" ? NSBezierPath(ovalIn: rect)
                : NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            if layer["color"] != nil { color(layer["color"], .white).setFill(); path.fill() }
            if let stroke = layer["stroke"] as? [String: Any] {
                color(stroke["color"], .white).setStroke()
                path.lineWidth = (num(stroke["width"]) ?? 0.004) * short
                path.stroke()
            }
            context.restoreGraphicsState()
            continue
        }
        guard let raw = layer["text"] as? String else { fail("\(out) layer \(k): text must be a string") }
        let text = layer["uppercase"] as? Bool ?? false ? raw.uppercased() : raw
        var points = (num(layer["size"]) ?? 0.08) * short
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ["left": .left, "right": .right][layer["align"] as? String ?? ""] ?? .center
        paragraph.lineHeightMultiple = num(layer["line_spacing"]) ?? 1
        func attributed(_ points: CGFloat) -> NSAttributedString {
            var a: [NSAttributedString.Key: Any] = [
                .font: font(layer, points), .foregroundColor: color(layer["color"], .white),
                .kern: (num(layer["tracking"]) ?? 0) * points, .paragraphStyle: paragraph,
            ]
            if let shadow = layer["shadow"] as? [String: Any] {
                let s = NSShadow()
                s.shadowColor = color(shadow["color"], NSColor.black.withAlphaComponent(0.6))
                s.shadowBlurRadius = (num(shadow["blur"]) ?? 0.02) * short
                s.shadowOffset = NSSize(width: (num(shadow["dx"]) ?? 0) * short, height: -(num(shadow["dy"]) ?? 0) * short)
                a[.shadow] = s
            }
            if let stroke = layer["stroke"] as? [String: Any] {
                a[.strokeColor] = color(stroke["color"], .black)
                a[.strokeWidth] = -(num(stroke["width"]) ?? 3) // percent of the font size; negative also fills
            }
            return NSAttributedString(string: text, attributes: a)
        }
        // Shrink to max_width (fraction of the width, default 0.9).
        var str = attributed(points)
        let maxWidth = (num(layer["max_width"]) ?? 0.9) * W
        if str.size().width > maxWidth { points *= maxWidth / str.size().width; str = attributed(points) }
        let size = str.size()
        // anchor says which point of the text block sits at (x, y).
        let anchor = layer["anchor"] as? String ?? "center"
        let ox = anchor.contains("left") ? 0 : anchor.contains("right") ? -size.width : -size.width / 2
        let oy = anchor.contains("top") ? -size.height : anchor.contains("bottom") ? 0 : -size.height / 2
        let textRect = NSRect(x: ox, y: oy, width: size.width, height: size.height)
        if let box = layer["box"] as? [String: Any] {
            let pad = (num(box["padding"]) ?? 0.25) * points
            let r = (num(box["radius"]) ?? 0) * short
            color(box["color"], NSColor.black.withAlphaComponent(0.5)).setFill()
            NSBezierPath(roundedRect: textRect.insetBy(dx: -pad * 1.4, dy: -pad), xRadius: r, yRadius: r).fill()
        }
        str.draw(with: textRect, options: [.usesLineFragmentOrigin])
        context.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("\(out): cannot encode PNG") }
    do { try png.write(to: URL(fileURLWithPath: safePath(out))) } catch { fail("cannot write \(out): \(error.localizedDescription)") }
    print("\(out) \(width)x\(height)")
}

// One image, or {"width", "height", ..., "images": [...]} with shared defaults.
if let images = spec["images"] as? [[String: Any]] {
    let defaults = spec.filter { $0.key != "images" }
    images.forEach { image($0, defaults: defaults) }
} else {
    image(spec, defaults: [:])
}
