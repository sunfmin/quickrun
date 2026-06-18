import XCTest
@testable import QuickRunKit

final class SaveLocationStoreTests: XCTestCase {
    private func makeStore() -> (SaveLocationStore, UserDefaults) {
        let suite = "SaveLocationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SaveLocationStore(defaults: defaults), defaults)
    }

    func testDefaultsToDesktopWhenUnset() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.folder(), SaveLocationStore.defaultFolder)
    }

    func testRoundTripsAChosenFolder() {
        let (store, _) = makeStore()
        let folder = URL(fileURLWithPath: "/Users/someone/Screenshots", isDirectory: true)
        store.setFolder(folder)
        XCTAssertEqual(store.folder().path, folder.path)
    }
}

final class CaptureFilenameTests: XCTestCase {
    func testProducesTimestampedPNGName() {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 18
        components.hour = 10; components.minute = 32; components.second = 45
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let name = captureFilename(date: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "QuickRun 2026-06-18 at 10.32.45.png")
    }

    func testTwoSecondsSortChronologically() {
        let utc = TimeZone(identifier: "UTC")!
        let earlier = captureFilename(date: Date(timeIntervalSince1970: 0), timeZone: utc)
        let later = captureFilename(date: Date(timeIntervalSince1970: 1), timeZone: utc)
        XCTAssertLessThan(earlier, later)
    }
}
