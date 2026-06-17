import XCTest
@testable import QuickRunKit

final class HotkeyStoreTests: XCTestCase {
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

    func testNilWhenUnset() {
        XCTAssertNil(HotkeyStore(defaults: defaults).load())
    }

    func testSaveRoundTripsAcrossInstances() {
        let hotkey = Hotkey(keyCode: 2, modifiers: 2048) // ⌥D
        HotkeyStore(defaults: defaults).save(hotkey)
        XCTAssertEqual(HotkeyStore(defaults: defaults).load(), hotkey)
    }

    func testSaveOverwrites() {
        let store = HotkeyStore(defaults: defaults)
        store.save(Hotkey(keyCode: 2, modifiers: 2048))
        store.save(Hotkey(keyCode: 49, modifiers: 256)) // ⌘Space
        XCTAssertEqual(store.load(), Hotkey(keyCode: 49, modifiers: 256))
    }
}
