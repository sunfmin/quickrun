import CoreGraphics
import Foundation

/// The Editor's fixed ink-and-width palette: the single source of truth for the
/// inline style strip's stroke-width presets and colour swatches. The strip UI
/// and the tests both read these — there is no second copy to drift.
public enum StylePresets {
    /// Thin / medium / thick stroke widths, shown as graded dots. `MarkupStyle`'s
    /// default width is the thin preset, so a fresh strip shows it selected.
    public static let widths: [Double] = [3, 5, 9]

    /// Curated markup inks, seal red first (the default stroke). One row, always
    /// visible — chosen over a deeper popover palette so the colours are
    /// predictable and reachable without a click.
    public static let colors: [RGBAColor] = [
        .sealRed,
        RGBAColor(red: 0.95, green: 0.45, blue: 0.18),  // orange
        RGBAColor(red: 0.96, green: 0.65, blue: 0.14),  // amber
        RGBAColor(red: 0.12, green: 0.67, blue: 0.41),  // jade
        RGBAColor(red: 0.18, green: 0.43, blue: 0.94),  // ocean
        RGBAColor(red: 0.49, green: 0.36, blue: 0.85),  // violet
        RGBAColor(red: 0.11, green: 0.11, blue: 0.12),  // ink
        RGBAColor(red: 1, green: 1, blue: 1),           // chalk
    ]
}
