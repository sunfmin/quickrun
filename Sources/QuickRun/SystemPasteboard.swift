import AppKit
import QuickRunKit

/// Real `PasteboardAccess` backed by `NSPasteboard.general`.
final class SystemPasteboard: PasteboardAccess {
    private let pb = NSPasteboard.general

    var string: String? {
        get { pb.string(forType: .string) }
        set {
            pb.clearContents()
            if let newValue { pb.setString(newValue, forType: .string) }
        }
    }

    var changeCount: Int { pb.changeCount }
}
