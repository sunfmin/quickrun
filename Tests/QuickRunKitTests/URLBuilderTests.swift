import XCTest
@testable import QuickRunKit

final class URLBuilderTests: XCTestCase {
    private let template = "https://cn.bing.com/dict/search?q={q}"

    func testBuildsExpectedURLs() throws {
        let cases: [(query: String, expected: String)] = [
            ("hello", "https://cn.bing.com/dict/search?q=hello"),
            ("hello world", "https://cn.bing.com/dict/search?q=hello%20world"),
            ("C&A", "https://cn.bing.com/dict/search?q=C%26A"),
            ("a?b#c/d=e", "https://cn.bing.com/dict/search?q=a%3Fb%23c%2Fd%3De"),
            ("日本語", "https://cn.bing.com/dict/search?q=%E6%97%A5%E6%9C%AC%E8%AA%9E"),
        ]
        for c in cases {
            let url = try URLBuilder.build(template: template, query: c.query)
            XCTAssertEqual(url.absoluteString, c.expected, "query=\(c.query)")
        }
    }

    func testMissingPlaceholderThrows() {
        XCTAssertThrowsError(try URLBuilder.build(template: "https://example.com/", query: "x")) {
            XCTAssertEqual($0 as? URLBuilderError, .missingPlaceholder)
        }
    }

    func testIsValidTemplate() {
        XCTAssertTrue(URLBuilder.isValidTemplate(template))
        XCTAssertFalse(URLBuilder.isValidTemplate("https://example.com/search"))
    }

    func testBuildFromSource() throws {
        let source = Source(name: "Bing", urlTemplate: template)
        let url = try URLBuilder.build(source: source, query: "test")
        XCTAssertEqual(url.absoluteString, "https://cn.bing.com/dict/search?q=test")
    }
}
