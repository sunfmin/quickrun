import CoreGraphics
import Foundation

/// What a mouse-down on the committed Capture region means, given the active
/// tool, the click point, and what sits under it.
///
/// The Editor view used to decide this with a nested if-else cascade whose
/// priority lived implicitly in control flow — overlap cases (a Recognized word
/// under a resize handle, a word over a mark) were silently unreachable and
/// untested. Resolving the click in one pure place turns that priority into a
/// table-driven test.
public enum EditorInteraction: Equatable {
    /// Drag a region edge or corner to resize the Capture.
    case resizeRegion(RegionSelection.Handle)
    /// Look up the Recognized word at this index into the supplied word rects.
    case lookUpWord(Int)
    /// Select an existing Markup object and begin moving it.
    case selectMark(UUID)
    /// Drag empty space inside the region to move the whole region.
    case moveRegion
    /// Empty space outside the region — clear the selection.
    case deselect
    /// Start a text label at this point.
    case beginText
    /// Stamp the current emoji at this point.
    case placeEmoji
    /// Start drawing a new mark with the active drawing tool.
    case drawMarkup

    /// Resolve a click on a committed region. Priority, highest first:
    ///
    /// 1. a resize handle (Select tool) — so an edge near a word or mark stays grabbable;
    /// 2. a Recognized word (Select tool) — looked up before it can start a mark;
    /// 3. an existing mark (Select tool), topmost first — selected and moved;
    /// 4. empty space inside the region (Select tool) — moves the whole region;
    /// 5. otherwise the active tool acts — text places a label, emoji stamps a
    ///    glyph, a drawing tool draws.
    ///
    /// `wordRects` are the clickable Recognized-word hit areas in region space,
    /// passed only when words are clickable (they are not while a drawing tool is
    /// active). `marks` are hit-tested last-on-top.
    public static func resolve(
        tool: MarkupTool,
        point: CGPoint,
        region: RegionSelection,
        handleTolerance: CGFloat,
        wordRects: [CGRect],
        marks: [MarkupObject]
    ) -> EditorInteraction {
        if tool == .select {
            if let handle = region.handle(at: point, tolerance: handleTolerance) {
                return .resizeRegion(handle)
            }
            if let index = wordRects.lastIndex(where: { $0.contains(point) }) {
                return .lookUpWord(index)
            }
            if let hit = marks.last(where: { $0.bounds.contains(point) }) {
                return .selectMark(hit.id)
            }
            if region.rect.contains(point) {
                return .moveRegion
            }
            return .deselect
        }
        switch tool {
        case .text: return .beginText
        case .emoji: return .placeEmoji
        default: return .drawMarkup
        }
    }
}
