// Draws a title or end card as a PNG, because Homebrew's ffmpeg has no drawtext.
// Usage: card <out.png> <width> <height> <style> <opaque|overlay> <text> [subtitle]
import AppKit

let args = CommandLine.arguments
guard args.count >= 7, let width = Int(args[2]), let height = Int(args[3]) else {
    FileHandle.standardError.write("usage: card <out.png> <width> <height> <style> <opaque|overlay> <text> [subtitle]\n".data(using: .utf8)!)
    exit(2)
}
let (out, style, opaque, text) = (args[1], args[4], args[5] == "opaque", args[6])
let subtitle = args.count > 7 ? args[7] : ""

let short = CGFloat(min(width, height))
let (weight, size, tracking): (NSFont.Weight, CGFloat, CGFloat) = switch style {
case "reels": (.heavy, 0.15, 0)
case "documentary": (.regular, 0.09, 2)
case "vlog": (.bold, 0.11, 0)
default: (.light, 0.10, 8) // cinematic
}
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
shadow.shadowBlurRadius = short * 0.02
func line(_ s: String, _ points: CGFloat, _ w: NSFont.Weight, _ kern: CGFloat) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: points, weight: w), .foregroundColor: NSColor.white,
        .kern: kern, .shadow: shadow,
    ])
}
// Shrink long text to fit 88 % of the width.
func fitted(_ s: String, _ points: CGFloat, _ w: NSFont.Weight, _ kern: CGFloat) -> NSAttributedString {
    let natural = line(s, points, w, kern)
    let scale = min(1, CGFloat(width) * 0.88 / max(natural.size().width, 1))
    return scale < 1 ? line(s, points * scale, w, kern * scale) : natural
}
let title = fitted(style == "reels" ? text.uppercased() : text, short * size, weight, tracking)
let sub = fitted(subtitle, short * size * 0.38, .medium, tracking / 2)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
(opaque ? NSColor.black : NSColor.clear).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
let titleSize = title.size(), subSize = sub.size()
let gap = subtitle.isEmpty ? 0 : short * 0.02
let block = titleSize.height + gap + (subtitle.isEmpty ? 0 : subSize.height)
let top = (CGFloat(height) + block) / 2
title.draw(at: NSPoint(x: (CGFloat(width) - titleSize.width) / 2, y: top - titleSize.height))
if !subtitle.isEmpty {
    sub.draw(at: NSPoint(x: (CGFloat(width) - subSize.width) / 2, y: top - titleSize.height - gap - subSize.height))
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: out)) } catch { exit(1) }
