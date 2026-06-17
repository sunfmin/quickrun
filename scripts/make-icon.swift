// Renders the QuickRun app icon: a gradient squircle with a magnifier framing
// the character 文 (text lookup). Writes a 1024×1024 PNG to argv[1].
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Rounded background with a diagonal gradient.
let bg = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.08, dy: size * 0.08)
let squircle = CGPath(roundedRect: bg, cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let colors = [
    NSColor(srgbRed: 0.36, green: 0.42, blue: 0.96, alpha: 1).cgColor,
    NSColor(srgbRed: 0.56, green: 0.29, blue: 0.93, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
ctx.restoreGState()

// Magnifier.
let cx = size * 0.45, cy = size * 0.55, r = size * 0.205
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineWidth(size * 0.058)
ctx.setLineCap(.round)
ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
ctx.move(to: CGPoint(x: cx + r * 0.72, y: cy - r * 0.72))
ctx.addLine(to: CGPoint(x: cx + r * 1.6, y: cy - r * 1.6))
ctx.strokePath()

// 文 centered in the lens.
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.2, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
]
let glyph = "文" as NSString
let glyphSize = glyph.size(withAttributes: attrs)
glyph.draw(at: CGPoint(x: cx - glyphSize.width / 2, y: cy - glyphSize.height / 2), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
