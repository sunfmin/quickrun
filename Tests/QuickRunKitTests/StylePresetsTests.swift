import XCTest
@testable import QuickRunKit

final class StylePresetsTests: XCTestCase {
    /// The strip rings whichever preset matches the current style. If the default
    /// style's width/ink weren't presets, a fresh strip would show nothing
    /// selected — so guard that the default is always reachable in the strip.
    func testDefaultStyleIsSelectableInTheStrip() {
        let style = MarkupStyle()
        XCTAssertTrue(StylePresets.widths.contains(style.lineWidth),
                      "default lineWidth must be one of the width presets")
        XCTAssertTrue(StylePresets.colors.contains(style.stroke),
                      "default stroke must be one of the colour presets")
    }

    func testPresetsAreNonEmptyAndDistinct() {
        XCTAssertFalse(StylePresets.widths.isEmpty)
        XCTAssertFalse(StylePresets.colors.isEmpty)
        XCTAssertEqual(StylePresets.widths.count, Set(StylePresets.widths).count, "no duplicate widths")
        XCTAssertEqual(StylePresets.colors.count, Set(StylePresets.colors.map(\.description)).count,
                       "no duplicate colours")
    }
}

private extension RGBAColor {
    var description: String { "\(red),\(green),\(blue),\(alpha)" }
}
