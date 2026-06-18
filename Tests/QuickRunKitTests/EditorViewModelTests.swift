import XCTest
@testable import QuickRunKit

final class EditorViewModelTests: XCTestCase {
    func testDefaultInitHasNoWords() {
        XCTAssertEqual(EditorViewModel().recognizedWords, [])
    }

    func testExposesRecognizedWords() {
        let vm = EditorViewModel(recognizedWords: ["alpha", "beta"])
        XCTAssertEqual(vm.recognizedWords, ["alpha", "beta"])
    }

    func testQueryForWordReturnsThatWord() {
        let vm = EditorViewModel(recognizedWords: ["alpha", "beta", "gamma"])
        XCTAssertEqual(vm.query(forWordAt: 1), "beta")
    }

    func testQueryOutOfRangeIsNil() {
        let vm = EditorViewModel(recognizedWords: ["alpha"])
        XCTAssertNil(vm.query(forWordAt: 9))
        XCTAssertNil(vm.query(forWordAt: -1))
    }
}
