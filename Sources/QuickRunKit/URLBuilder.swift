import Foundation

/// The placeholder a Source's URL template must contain.
public let queryPlaceholder = "{q}"

public enum URLBuilderError: Error, Equatable {
    /// The template did not contain the `{q}` placeholder.
    case missingPlaceholder
    /// Substitution produced a string that is not a valid URL.
    case malformedURL
}

/// Substitutes a percent-encoded Query into a Source's URL template.
public enum URLBuilder {
    /// Whether a template is usable — i.e. it contains the `{q}` placeholder.
    public static func isValidTemplate(_ template: String) -> Bool {
        template.contains(queryPlaceholder)
    }

    /// Build the final URL for `source` looking up `query`.
    public static func build(source: Source, query: String) throws -> URL {
        try build(template: source.urlTemplate, query: query)
    }

    /// Build the final URL by substituting the percent-encoded `query` for `{q}`.
    public static func build(template: String, query: String) throws -> URL {
        guard template.contains(queryPlaceholder) else {
            throw URLBuilderError.missingPlaceholder
        }
        let substituted = template.replacingOccurrences(
            of: queryPlaceholder,
            with: encode(query)
        )
        guard let url = URL(string: substituted) else {
            throw URLBuilderError.malformedURL
        }
        return url
    }

    /// Percent-encode text for safe use inside a URL query value.
    /// Encodes everything outside the RFC 3986 unreserved set, so spaces,
    /// CJK, `&`, `?`, `#`, `=` and `/` are all escaped.
    static func encode(_ query: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
