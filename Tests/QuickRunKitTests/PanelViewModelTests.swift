import XCTest
@testable import QuickRunKit

final class PanelViewModelTests: XCTestCase {
    private let sources = [
        Source(name: "Bing", urlTemplate: "https://bing.com/?q={q}"),
        Source(name: "Youdao", urlTemplate: "https://youdao.com/?w={q}"),
        Source(name: "Google", urlTemplate: "https://google.com/?s={q}"),
    ]

    func testOpenLoadsOnlyActiveTab() {
        let vm = PanelViewModel(sources: sources)
        let req = vm.open(selection: "hello")
        XCTAssertEqual(req, LoadRequest(index: 0, url: URL(string: "https://bing.com/?q=hello")!))
        XCTAssertEqual(vm.states, [.loading, .unloaded, .unloaded])
        XCTAssertEqual(vm.activeIndex, 0)
    }

    func testEmptySelectionLoadsNothing() {
        let vm = PanelViewModel(sources: sources)
        XCTAssertNil(vm.open(selection: "   "))
        XCTAssertEqual(vm.states, [.unloaded, .unloaded, .unloaded])
    }

    func testSwitchLoadsUnloadedTabWithItsOwnSource() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "hello")
        vm.loadDidFinish(0)

        let req = vm.switchTo(1)
        XCTAssertEqual(req, LoadRequest(index: 1, url: URL(string: "https://youdao.com/?w=hello")!))
        XCTAssertEqual(vm.states, [.loaded, .loading, .unloaded])
    }

    func testSwitchToLoadedTabDoesNotReload() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "hello")
        vm.loadDidFinish(0)
        vm.switchTo(1)
        vm.loadDidFinish(1)

        XCTAssertNil(vm.switchTo(0))
        XCTAssertEqual(vm.states, [.loaded, .loaded, .unloaded])
    }

    func testSubmitReloadsActiveAndStalesOthers() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "hello")
        vm.loadDidFinish(0)
        vm.switchTo(1)
        vm.loadDidFinish(1)
        vm.switchTo(0) // active = 0, loaded

        let req = vm.submit(query: "world")
        XCTAssertEqual(req, LoadRequest(index: 0, url: URL(string: "https://bing.com/?q=world")!))
        XCTAssertEqual(vm.states, [.loading, .stale, .stale])
    }

    func testStaleTabReloadsWithNewQueryOnSwitch() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "hello")
        vm.loadDidFinish(0)
        vm.switchTo(1)
        vm.loadDidFinish(1)
        vm.switchTo(0)
        vm.submit(query: "world") // tab 1 is now stale

        let req = vm.switchTo(1)
        XCTAssertEqual(req, LoadRequest(index: 1, url: URL(string: "https://youdao.com/?w=world")!))
        XCTAssertEqual(vm.states[1], .loading)
    }

    func testQueryIsPreservedAcrossTabSwitch() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "cat")
        // Switching tabs must not clobber the Query: the field projects this
        // value, so it stays consistent with what the active tab loads.
        vm.switchTo(1)
        XCTAssertEqual(vm.query, "cat")
        vm.switchTo(2)
        XCTAssertEqual(vm.query, "cat")
    }

    func testSubmitUpdatesTheQuery() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "cat")
        vm.submit(query: "dog")
        XCTAssertEqual(vm.query, "dog")
    }

    func testSwitchOutOfRangeIsIgnored() {
        let vm = PanelViewModel(sources: sources)
        vm.open(selection: "hello")
        XCTAssertNil(vm.switchTo(9))
        XCTAssertEqual(vm.activeIndex, 0)
    }
}
