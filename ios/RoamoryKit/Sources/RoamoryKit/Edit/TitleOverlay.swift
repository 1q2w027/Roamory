import AVFoundation
import CoreText
import QuartzCore

/// Title, captions and end-card text drawn over the video with Core Animation.
/// Layer geometry has its origin at the bottom left, as AVFoundation renders it.
enum TitleOverlay {
    struct Caption {
        var text: String
        var startS: Double
        var endS: Double
    }

    static func animationTool(
        title: EditSpec.Title, captions: [Caption], endCard: EditSpec.EndCard, endCardStartS: Double, renderSize: CGSize
    ) -> AVVideoCompositionCoreAnimationTool {
        let bounds = CGRect(origin: .zero, size: renderSize)
        let parent = CALayer()
        parent.frame = bounds
        let video = CALayer()
        video.frame = bounds
        parent.addSublayer(video)

        let unit = min(renderSize.width, renderSize.height)
        let margin = unit * 0.08

        let titleGroup = CALayer()
        titleGroup.frame = bounds
        let titleSize = unit * 0.11
        let titleFrame = CGRect(x: margin, y: renderSize.height / 2 - titleSize * 0.2, width: renderSize.width - 2 * margin, height: titleSize * 1.3)
        titleGroup.addSublayer(textLayer(title.text, size: titleSize, bold: true, frame: titleFrame))
        if let subtitle = title.subtitle, !subtitle.isEmpty {
            let size = unit * 0.05
            let frame = CGRect(x: margin, y: titleFrame.minY - size * 1.6, width: titleFrame.width, height: size * 1.3)
            titleGroup.addSublayer(textLayer(subtitle, size: size, bold: false, frame: frame))
        }
        show(titleGroup, from: 0, to: title.durationS, fadeOut: true)
        parent.addSublayer(titleGroup)

        for caption in captions {
            let size = unit * 0.045
            let frame = CGRect(x: margin, y: margin, width: renderSize.width - 2 * margin, height: size * 1.3 * 2)
            let layer = textLayer(caption.text, size: size, bold: false, frame: frame, lines: 2)
            show(layer, from: caption.startS, to: caption.endS, fadeOut: true)
            parent.addSublayer(layer)
        }

        let endSize = unit * 0.06
        let endFrame = CGRect(x: margin, y: renderSize.height / 2 - endSize * 0.65, width: renderSize.width - 2 * margin, height: endSize * 1.3)
        let endLayer = textLayer(endCard.text, size: endSize, bold: true, frame: endFrame)
        show(endLayer, from: endCardStartS, to: endCardStartS + endCard.durationS, fadeOut: false)
        parent.addSublayer(endLayer)

        return AVVideoCompositionCoreAnimationTool(configuration: .init(postProcessingAsVideoLayer: video, containingLayer: parent))
    }

    /// Text drawn into an image up front. A CATextLayer draws only when Core Animation runs a display pass,
    /// which offscreen video rendering doesn't reliably do, so its text can come out blank.
    private static func textLayer(_ text: String, size: CGFloat, bold: Bool, frame: CGRect, lines: Int = 1) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = textImage(text, size: size, bold: bold, canvas: frame.size, singleLine: lines == 1)
        return layer
    }

    /// White, centered, with a soft shadow. A single line shrinks (to half size at most) to fit the width.
    static func textImage(_ text: String, size: CGFloat, bold: Bool, canvas: CGSize, singleLine: Bool) -> CGImage? {
        let width = Int(canvas.width.rounded(.up)), height = Int(canvas.height.rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        func attributed(_ fontSize: CGFloat) -> NSAttributedString {
            var alignment = CTTextAlignment.center
            let paragraph = withUnsafeBytes(of: &alignment) { bytes in
                [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: bytes.baseAddress!)]
                    .withUnsafeBufferPointer { CTParagraphStyleCreate($0.baseAddress, $0.count) }
            }
            return NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, fontSize, nil)!,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ])
        }

        var fontSize = size
        if singleLine {
            let lineWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(size)), nil, nil, nil)
            if lineWidth > canvas.width { fontSize = max(size / 2, size * canvas.width / lineWidth * 0.98) }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(fontSize))
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: canvas.width, height: .greatestFiniteMagnitude), nil)
        let textHeight = min(fit.height.rounded(.up), canvas.height)
        let rect = CGRect(x: 0, y: (canvas.height - textHeight) / 2, width: canvas.width, height: textHeight)

        context.setShadow(offset: .zero, blur: fontSize * 0.15, color: CGColor(gray: 0, alpha: 0.8))
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil), context)
        return context.makeImage()
    }

    /// Visible over [start, end] with short fades; hidden otherwise.
    private static func show(_ layer: CALayer, from start: Double, to end: Double, fadeOut: Bool) {
        let duration = end - start
        guard duration > 0 else { return }
        layer.opacity = 0
        let fade = min(0.4, duration / 4)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, fadeOut ? 0 : 1]
        animation.keyTimes = [0, fade / duration, (duration - fade) / duration, 1].map { NSNumber(value: $0) }
        // 0 would mean "now" to Core Animation.
        animation.beginTime = start == 0 ? AVCoreAnimationBeginTimeAtZero : start
        animation.duration = duration
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: "show")
    }
}
