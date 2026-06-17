import Foundation

/// Load state of a single Source tab.
public enum TabLoadState: Equatable {
    case unloaded
    case loading
    case loaded
    /// Previously loaded, but the Query changed — reload when next shown.
    case stale
}

/// A request for the controller to load `url` into the WKWebView for `index`.
public struct LoadRequest: Equatable {
    public let index: Int
    public let url: URL

    public init(index: Int, url: URL) {
        self.index = index
        self.url = url
    }
}

/// Drives the Panel's tabs and lazy loading without touching WebKit.
///
/// Only the active tab loads. Switching to an `unloaded` or `stale` tab loads
/// it. Submitting a Query reloads the active tab and marks the others `stale`.
/// Each mutating method returns the `LoadRequest` the controller should execute
/// (or `nil` when nothing needs loading); the controller reports completion via
/// `loadDidFinish(_:)`.
public final class PanelViewModel {
    public private(set) var sources: [Source]
    public private(set) var query: String
    public private(set) var activeIndex: Int
    public private(set) var states: [TabLoadState]

    public init(sources: [Source], query: String = "") {
        self.sources = sources
        self.query = query
        self.activeIndex = 0
        self.states = Array(repeating: .unloaded, count: sources.count)
    }

    /// Open the Panel for a fresh Selection: reset all tabs, focus the first,
    /// and load it if the Query is non-empty.
    @discardableResult
    public func open(selection: String) -> LoadRequest? {
        query = selection
        activeIndex = 0
        states = Array(repeating: .unloaded, count: sources.count)
        return loadActiveIfNeeded()
    }

    /// Switch to a tab, loading it if it is `unloaded` or `stale`.
    @discardableResult
    public func switchTo(_ index: Int) -> LoadRequest? {
        guard sources.indices.contains(index) else { return nil }
        activeIndex = index
        return loadActiveIfNeeded()
    }

    /// Re-run with an edited Query: reload the active tab now, stale the rest.
    @discardableResult
    public func submit(query newQuery: String) -> LoadRequest? {
        query = newQuery
        for i in states.indices where i != activeIndex {
            states[i] = .stale
        }
        states[activeIndex] = .unloaded
        return loadActiveIfNeeded()
    }

    /// Mark a tab loaded once its WKWebView finishes navigating.
    public func loadDidFinish(_ index: Int) {
        guard states.indices.contains(index) else { return }
        states[index] = .loaded
    }

    private func loadActiveIfNeeded() -> LoadRequest? {
        guard sources.indices.contains(activeIndex) else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let state = states[activeIndex]
        guard state == .unloaded || state == .stale else { return nil }
        guard let url = try? URLBuilder.build(source: sources[activeIndex], query: trimmed) else { return nil }

        states[activeIndex] = .loading
        return LoadRequest(index: activeIndex, url: url)
    }
}
