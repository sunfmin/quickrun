import Foundation

/// Persists the folder where saved Captures are written, in an injected
/// `UserDefaults`. Mirrors `HotkeyStore`. With nothing chosen, Captures save to
/// the Desktop, matching where macOS screenshots land.
public final class SaveLocationStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "QuickRun.saveLocation") {
        self.defaults = defaults
        self.key = key
    }

    /// The chosen folder, or the Desktop if the user hasn't picked one.
    public func folder() -> URL {
        if let path = defaults.string(forKey: key) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultFolder
    }

    public func setFolder(_ url: URL) {
        defaults.set(url.path, forKey: key)
    }

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}

/// The timestamped file name for a saved Capture, e.g.
/// `QuickRun 2026-06-18 at 10.32.45.png`. Modelled on macOS screenshot names so
/// files sort chronologically and never collide within a second.
public func captureFilename(date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "QuickRun \(formatter.string(from: date)).png"
}
