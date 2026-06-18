import XCTest
@testable import QuickRunKit

final class LookupRouterTests: XCTestCase {

    func testNilSelectionCaptures() {
        XCTAssertEqual(LookupRouter.route(selection: nil), .capture)
    }

    func testEmptySelectionCaptures() {
        XCTAssertEqual(LookupRouter.route(selection: ""), .capture)
    }

    func testWhitespaceOnlySelectionCaptures() {
        XCTAssertEqual(LookupRouter.route(selection: "   "), .capture)
        XCTAssertEqual(LookupRouter.route(selection: "\n\t  "), .capture)
    }

    func testNonEmptySelectionOpensPanel() {
        XCTAssertEqual(LookupRouter.route(selection: "hello"), .panel(query: "hello"))
    }

    func testSelectionIsTrimmed() {
        XCTAssertEqual(LookupRouter.route(selection: "  hello  "), .panel(query: "hello"))
        XCTAssertEqual(LookupRouter.route(selection: "\nword\t"), .panel(query: "word"))
    }

    func testInteriorWhitespaceIsKept() {
        XCTAssertEqual(LookupRouter.route(selection: "  多字 word  "), .panel(query: "多字 word"))
    }
}
