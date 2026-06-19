import XCTest
@testable import QuickRunKit

final class SourceLibraryTests: XCTestCase {
    // MARK: - Catalog guards

    /// The whole point of bundling a curated catalog: a typo in any template
    /// can't ship. Every entry must contain `{q}` and build a valid URL for a
    /// plain word, a multi-word phrase, and a CJK term.
    func testEveryEntryBuildsAValidURL() throws {
        let queries = ["hello", "hello world", "日本語"]
        for entry in SourceLibrary.catalog {
            XCTAssertTrue(
                URLBuilder.isValidTemplate(entry.urlTemplate),
                "\(entry.name) template is missing {q}: \(entry.urlTemplate)"
            )
            for query in queries {
                XCTAssertNoThrow(
                    try URLBuilder.build(template: entry.urlTemplate, query: query),
                    "\(entry.name) failed to build for query=\(query)"
                )
            }
        }
    }

    func testCatalogIsWellFormed() {
        XCTAssertFalse(SourceLibrary.catalog.isEmpty)
        for entry in SourceLibrary.catalog {
            XCTAssertFalse(entry.name.isEmpty)
            XCTAssertFalse(entry.urlTemplate.isEmpty)
            XCTAssertFalse(entry.category.isEmpty)
        }
    }

    /// The catalog itself is deduped — two entries sharing a template would make
    /// dedup-by-template ambiguous and surface as a confusing picker.
    func testNoDuplicateTemplatesInCatalog() {
        let templates = SourceLibrary.catalog.map(\.urlTemplate)
        XCTAssertEqual(Set(templates).count, templates.count, "duplicate urlTemplate in catalog")
    }

    func testCategoriesAreOrderedAndCoverEntries() {
        let categories = SourceLibrary.categories
        XCTAssertEqual(Set(categories).count, categories.count, "categories should be de-duplicated")
        // Every entry's category is listed, and every listed category has entries.
        for category in categories {
            XCTAssertFalse(SourceLibrary.entries(in: category).isEmpty)
        }
        let fromEntries = Set(SourceLibrary.catalog.map(\.category))
        XCTAssertEqual(Set(categories), fromEntries)
    }

    // MARK: - Add operation

    private func entry(_ name: String, _ template: String) -> CatalogEntry {
        CatalogEntry(name: name, urlTemplate: template, category: "test")
    }

    private func source(_ name: String, _ template: String) -> Source {
        Source(name: name, urlTemplate: template)
    }

    func testNewSourcesMintsFreshIdsForEachEntry() {
        let entries = [
            entry("A", "https://a.example/?q={q}"),
            entry("B", "https://b.example/?q={q}"),
        ]
        let minted = SourceLibrary.newSources(for: entries, existing: [])
        XCTAssertEqual(minted.map(\.name), ["A", "B"])
        XCTAssertEqual(minted.map(\.urlTemplate), entries.map(\.urlTemplate))
        XCTAssertEqual(Set(minted.map(\.id)).count, 2, "each added Source gets its own id")
    }

    func testDedupIsByTemplateNotName() {
        // The user renamed a Source but kept its template; adding the catalog
        // entry it came from must NOT create a second copy.
        let existing = [source("必应词典 (renamed)", "https://cn.bing.com/dict/search?q={q}")]
        let minted = SourceLibrary.newSources(
            for: [entry("必应词典", "https://cn.bing.com/dict/search?q={q}")],
            existing: existing
        )
        XCTAssertTrue(minted.isEmpty)
    }

    func testDedupWithinTheSameSelection() {
        let dup = entry("X", "https://x.example/?q={q}")
        let minted = SourceLibrary.newSources(for: [dup, dup], existing: [])
        XCTAssertEqual(minted.count, 1)
    }

    func testAddAppendsAfterExistingPreservingOrder() {
        let existing = [source("Keep", "https://keep.example/?q={q}")]
        let result = SourceLibrary.add(
            [entry("New", "https://new.example/?q={q}")],
            to: existing
        )
        XCTAssertEqual(result.map(\.name), ["Keep", "New"])
    }

    func testReAddAfterRemovalGetsANewId() {
        let e = entry("Z", "https://z.example/?q={q}")
        let first = SourceLibrary.newSources(for: [e], existing: [])
        // Source removed (existing empty again), re-add: new id, not the old one.
        let second = SourceLibrary.newSources(for: [e], existing: [])
        XCTAssertNotEqual(first.first?.id, second.first?.id)
    }
}
