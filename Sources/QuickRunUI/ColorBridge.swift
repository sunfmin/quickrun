import AppKit
import QuickRunKit

/// Bridges the AppKit-free `RGBAColor` model (QuickRunKit) to `NSColor` and back.
/// Lives in the UI layer because QuickRunKit deliberately does not import AppKit;
/// the app and the toolbar views both reach it through `import QuickRunUI`.
extension NSColor {
    public convenience init(_ color: RGBAColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    public var rgba: RGBAColor {
        let c = usingColorSpace(.sRGB) ?? self
        return RGBAColor(red: Double(c.redComponent), green: Double(c.greenComponent),
                         blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }
}
