import Foundation

/// Where the hotkey leads, given what (if anything) was selected.
public enum LookupRoute: Equatable {
    /// Nothing usable was selected — capture a screen region instead.
    case capture
    /// A word to look up — open the Panel seeded with this Query.
    case panel(query: String)
}

/// Turns a Selection into the hotkey's destination. This rule — empty or
/// whitespace-only Selection means "capture", otherwise "look up the trimmed
/// Query" — used to live inline in `AppDelegate.trigger()`, untested, next to
/// permission checks and window creation. Pulling it into a pure module makes
/// the decision the test surface.
public enum LookupRouter {
    public static func route(selection: String?) -> LookupRoute {
        let query = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return query.isEmpty ? .capture : .panel(query: query)
    }
}
