import XCTest
import CoreGraphics
@testable import QuickRunKit

final class EditorViewModelTests: XCTestCase {
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> MarkupObject {
        MarkupObject(kind: .rectangle(CGRect(x: x, y: y, width: w, height: h)))
    }

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

    func testSelectWordYieldsLookUpIntent() {
        let vm = EditorViewModel(recognizedWords: ["alpha", "beta"])
        XCTAssertEqual(vm.selectWord(at: 1), .lookUp("beta"))
        XCTAssertNil(vm.selectWord(at: 9))
    }

    func testCopyYieldsCopyIntent() {
        XCTAssertEqual(EditorViewModel().copy(), .copyToClipboard)
    }

    func testStartsOnSelectTool() {
        XCTAssertEqual(EditorViewModel().currentTool, .select)
    }

    func testSelectingDrawToolClearsObjectSelection() {
        let vm = EditorViewModel()
        vm.addObject(rect(0, 0, 10, 10))
        XCTAssertNotNil(vm.selectedObjectID)
        vm.selectTool(.rectangle)
        XCTAssertNil(vm.selectedObjectID)
        XCTAssertEqual(vm.currentTool, .rectangle)
    }

    func testAddObjectSelectsIt() {
        let vm = EditorViewModel()
        let object = rect(0, 0, 10, 10)
        vm.addObject(object)
        XCTAssertEqual(vm.selectedObjectID, object.id)
        XCTAssertEqual(vm.document.objects.map(\.id), [object.id])
    }

    func testDeleteSelectionRemovesAndClears() {
        let vm = EditorViewModel()
        vm.addObject(rect(0, 0, 10, 10))
        vm.deleteSelection()
        XCTAssertTrue(vm.document.objects.isEmpty)
        XCTAssertNil(vm.selectedObjectID)
    }

    func testMoveSelectionTranslatesObject() {
        let vm = EditorViewModel()
        let object = rect(0, 0, 10, 10)
        vm.addObject(object)
        vm.moveSelection(by: CGSize(width: 4, height: 6))
        XCTAssertEqual(vm.document.objects.first?.bounds, CGRect(x: 4, y: 6, width: 10, height: 10))
    }

    func testSetStyleRestylesSelectionAndSetsDefault() {
        let vm = EditorViewModel()
        vm.addObject(rect(0, 0, 10, 10))
        let style = MarkupStyle(stroke: RGBAColor(red: 0, green: 0, blue: 1), lineWidth: 8)
        vm.setStyle(style)
        XCTAssertEqual(vm.document.objects.first?.style, style)
        XCTAssertEqual(vm.defaultStyle, style)
    }

    func testSetStyleWithNoSelectionOnlyChangesDefault() {
        let vm = EditorViewModel()
        let style = MarkupStyle(stroke: .sealRed, lineWidth: 8)
        vm.setStyle(style)
        XCTAssertEqual(vm.defaultStyle, style)
        XCTAssertTrue(vm.document.objects.isEmpty)
    }

    func testUndoDropsSelectionWhenObjectDisappears() {
        let vm = EditorViewModel()
        vm.addObject(rect(0, 0, 10, 10))
        vm.undo() // removes the just-added object
        XCTAssertNil(vm.selectedObjectID)
        XCTAssertTrue(vm.document.objects.isEmpty)
    }
}
