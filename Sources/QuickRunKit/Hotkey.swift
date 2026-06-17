import Foundation

/// A global hotkey identified by its raw virtual key code and Carbon modifier
/// mask. Matching is on the key code, never the produced character — so an
/// option-letter combo whose character is a dead key (⌥D → ∂) still works.
public struct Hotkey: Equatable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Persists the user's chosen `Hotkey` in an injected `UserDefaults`.
public final class HotkeyStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "QuickRun.hotkey") {
        self.defaults = defaults
        self.key = key
    }

    /// The stored hotkey, or nil if the user hasn't chosen one (use the default).
    public func load() -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    public func save(_ hotkey: Hotkey) {
        defaults.set(try? JSONEncoder().encode(hotkey), forKey: key)
    }
}
