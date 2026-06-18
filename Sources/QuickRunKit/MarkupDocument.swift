import CoreGraphics
import Foundation

/// The ordered set of Markup objects over a Capture, with undo/redo.
///
/// Objects are stored back-to-front: the last element draws on top and is hit
/// first. Undo/redo snapshot the whole object list, so any edit — add, restyle,
/// move, delete — is one reversible step. A mutation that changes nothing (e.g.
/// removing an unknown id) is dropped and does not pollute the undo stack.
public final class MarkupDocument {
    public private(set) var objects: [MarkupObject]
    private var undoStack: [[MarkupObject]] = []
    private var redoStack: [[MarkupObject]] = []

    public init(objects: [MarkupObject] = []) {
        self.objects = objects
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func add(_ object: MarkupObject) {
        mutate { $0.append(object) }
    }

    /// Replace the object sharing `object.id` (used for restyle and resize).
    public func update(_ object: MarkupObject) {
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == object.id }) {
                list[index] = object
            }
        }
    }

    public func remove(id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    /// Translate the object with `id` by `offset`.
    public func move(id: UUID, by offset: CGSize) {
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == id }) {
                list[index] = list[index].translated(by: offset)
            }
        }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(objects)
        objects = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(objects)
        objects = next
    }

    /// The topmost object whose bounds contain `point` (capture space), if any.
    public func object(at point: CGPoint) -> MarkupObject? {
        objects.last { $0.bounds.contains(point) }
    }

    private func mutate(_ change: (inout [MarkupObject]) -> Void) {
        var next = objects
        change(&next)
        guard next != objects else { return } // no-op: don't create an undo step
        undoStack.append(objects)
        redoStack.removeAll()
        objects = next
    }
}
