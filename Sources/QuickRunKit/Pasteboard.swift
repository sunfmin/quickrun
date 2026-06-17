import Foundation

/// Minimal abstraction over the system pasteboard so Selection-capture logic
/// can be unit-tested without touching the real `NSPasteboard`.
public protocol PasteboardAccess: AnyObject {
    var string: String? { get set }
    /// Monotonically increasing counter that changes whenever the contents change.
    var changeCount: Int { get }
}
