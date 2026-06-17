import XCTest
@testable import QuickRunKit

final class SourceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "QuickRunTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> UserDefaultsSourceStore {
        UserDefaultsSourceStore(defaults: defaults)
    }

    private func source(_ name: String) -> Source {
        Source(name: name, urlTemplate: "https://example.com/?q={q}")
    }

    func testEmptyByDefault() {
        XCTAssertEqual(makeStore().load(), [])
    }

    func testAddPersistsAcrossInstances() {
        makeStore().add(source("Bing"))
        // A fresh store over the same defaults sees the persisted Source.
        let reloaded = makeStore().load()
        XCTAssertEqual(reloaded.map(\.name), ["Bing"])
    }

    func testUpdateChangesMatchingSource() {
        let store = makeStore()
        var s = source("Bing")
        store.add(s)
        s.name = "必应"
        store.update(s)
        XCTAssertEqual(makeStore().load().map(\.name), ["必应"])
    }

    func testRemoveDropsSource() {
        let store = makeStore()
        let a = source("A")
        let b = source("B")
        store.add(a)
        store.add(b)
        store.remove(id: a.id)
        XCTAssertEqual(makeStore().load().map(\.name), ["B"])
    }

    func testMoveReordersAndPersists() {
        let store = makeStore()
        store.add(source("A"))
        store.add(source("B"))
        store.add(source("C"))
        store.move(from: 0, to: 2)
        XCTAssertEqual(makeStore().load().map(\.name), ["B", "C", "A"])
    }

    func testSeedIfEmptyOnlySeedsOnce() {
        let store = makeStore()
        store.seedIfEmpty([source("Default")])
        store.seedIfEmpty([source("Other")]) // ignored — not empty
        XCTAssertEqual(makeStore().load().map(\.name), ["Default"])
    }
}
