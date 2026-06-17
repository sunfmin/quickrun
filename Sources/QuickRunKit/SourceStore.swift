import Foundation

/// Persists the user's Sources as JSON in `UserDefaults`. The defaults instance
/// is injected so the store can be exercised against an ephemeral suite in
/// tests. This is the single store for Sources — there is no hand-editable file.
public final class UserDefaultsSourceStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "QuickRun.sources") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [Source] {
        guard let data = defaults.data(forKey: key),
              let sources = try? JSONDecoder().decode([Source].self, from: data)
        else { return [] }
        return sources
    }

    /// Persist `sources` if none are stored yet (first-run defaults).
    public func seedIfEmpty(_ sources: [Source]) {
        if load().isEmpty { persist(sources) }
    }

    @discardableResult
    public func add(_ source: Source) -> [Source] {
        var sources = load()
        sources.append(source)
        persist(sources)
        return sources
    }

    @discardableResult
    public func update(_ source: Source) -> [Source] {
        var sources = load()
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        }
        persist(sources)
        return sources
    }

    @discardableResult
    public func remove(id: UUID) -> [Source] {
        var sources = load()
        sources.removeAll { $0.id == id }
        persist(sources)
        return sources
    }

    @discardableResult
    public func move(from: Int, to: Int) -> [Source] {
        var sources = load()
        guard sources.indices.contains(from), to >= 0, to <= sources.count, from != to else {
            return sources
        }
        let item = sources.remove(at: from)
        sources.insert(item, at: min(to, sources.count))
        persist(sources)
        return sources
    }

    /// Replace the whole list (used by the Settings editor when it owns a
    /// working copy).
    public func replaceAll(_ sources: [Source]) {
        persist(sources)
    }

    private func persist(_ sources: [Source]) {
        defaults.set(try? JSONEncoder().encode(sources), forKey: key)
    }
}
