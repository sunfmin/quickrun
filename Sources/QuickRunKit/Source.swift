import Foundation

/// One configured lookup target: a display name plus a URL template
/// containing a `{q}` placeholder for the Query.
public struct Source: Equatable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var urlTemplate: String

    public init(id: UUID = UUID(), name: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
    }
}
