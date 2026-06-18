import XCTest
import CoreGraphics
@testable import QuickRunKit

final class MarkupDocumentTests: XCTestCase {
    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> MarkupObject {
        MarkupObject(kind: .rectangle(CGRect(x: x, y: y, width: w, height: h)))
    }

    func testAddAppendsInZOrder() {
        let doc = MarkupDocument()
        let a = rect(0, 0, 10, 10), b = rect(5, 5, 10, 10)
        doc.add(a)
        doc.add(b)
        XCTAssertEqual(doc.objects.map(\.id), [a.id, b.id])
    }

    func testUpdateReplacesById() {
        let doc = MarkupDocument()
        var a = rect(0, 0, 10, 10)
        doc.add(a)
        a.style = MarkupStyle(stroke: .sealRed, lineWidth: 9)
        doc.update(a)
        XCTAssertEqual(doc.objects.first?.style.lineWidth, 9)
    }

    func testRemoveById() {
        let doc = MarkupDocument()
        let a = rect(0, 0, 10, 10), b = rect(5, 5, 10, 10)
        doc.add(a); doc.add(b)
        doc.remove(id: a.id)
        XCTAssertEqual(doc.objects.map(\.id), [b.id])
    }

    func testMoveTranslatesGeometry() {
        let doc = MarkupDocument()
        let a = rect(0, 0, 10, 10)
        doc.add(a)
        doc.move(id: a.id, by: CGSize(width: 5, height: 3))
        XCTAssertEqual(doc.objects.first?.bounds, CGRect(x: 5, y: 3, width: 10, height: 10))
    }

    func testUndoRestoresPreviousState() {
        let doc = MarkupDocument()
        doc.add(rect(0, 0, 10, 10))
        XCTAssertTrue(doc.canUndo)
        doc.undo()
        XCTAssertTrue(doc.objects.isEmpty)
        XCTAssertFalse(doc.canUndo)
    }

    func testRedoReappliesUndoneState() {
        let doc = MarkupDocument()
        let a = rect(0, 0, 10, 10)
        doc.add(a)
        doc.undo()
        doc.redo()
        XCTAssertEqual(doc.objects.map(\.id), [a.id])
        XCTAssertFalse(doc.canRedo)
    }

    func testUndoPastStartIsNoOp() {
        let doc = MarkupDocument()
        doc.undo() // nothing to undo
        XCTAssertTrue(doc.objects.isEmpty)
    }

    func testRedoPastEndIsNoOp() {
        let doc = MarkupDocument()
        doc.add(rect(0, 0, 10, 10))
        doc.redo() // nothing to redo
        XCTAssertEqual(doc.objects.count, 1)
    }

    func testNewMutationClearsRedo() {
        let doc = MarkupDocument()
        doc.add(rect(0, 0, 10, 10))
        doc.undo()              // redo now available
        XCTAssertTrue(doc.canRedo)
        doc.add(rect(1, 1, 2, 2)) // a fresh edit invalidates redo
        XCTAssertFalse(doc.canRedo)
    }

    func testNoOpMutationCreatesNoUndoStep() {
        let doc = MarkupDocument()
        doc.remove(id: UUID()) // unknown id changes nothing
        XCTAssertFalse(doc.canUndo)
    }

    func testHitTestReturnsTopmostObject() {
        let doc = MarkupDocument()
        let lower = rect(0, 0, 20, 20), upper = rect(0, 0, 20, 20)
        doc.add(lower); doc.add(upper)
        XCTAssertEqual(doc.object(at: CGPoint(x: 10, y: 10))?.id, upper.id)
        XCTAssertNil(doc.object(at: CGPoint(x: 100, y: 100)))
    }
}
