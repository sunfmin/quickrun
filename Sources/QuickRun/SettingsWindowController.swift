import AppKit
import QuickRunKit

/// Settings window: a table of Sources (name + URL template) with add / remove /
/// move, persisted through the SourceStore. A URL template missing the `{q}`
/// placeholder is rejected on commit.
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store: UserDefaultsSourceStore
    private var sources: [Source]
    private let window: NSWindow
    private let tableView = NSTableView()

    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let urlColumn = NSUserInterfaceItemIdentifier("url")

    init(store: UserDefaultsSourceStore) {
        self.store = store
        self.sources = store.load()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "QuickRun Settings"
        window.isReleasedWhenClosed = false
        buildUI()
    }

    func show() {
        sources = store.load()
        tableView.reloadData()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func buildUI() {
        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 48, width: 576, height: 296))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let nameCol = NSTableColumn(identifier: Self.nameColumn)
        nameCol.title = "Name"
        nameCol.width = 160
        let urlCol = NSTableColumn(identifier: Self.urlColumn)
        urlCol.title = "URL template (must contain {q})"
        urlCol.width = 396
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(urlCol)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        scroll.documentView = tableView
        content.addSubview(scroll)

        let add = button("＋ Add", #selector(addSource), x: 12)
        let remove = button("－ Remove", #selector(removeSource), x: 92)
        let up = button("Move Up", #selector(moveUp), x: 188)
        let down = button("Move Down", #selector(moveDown), x: 280)
        [add, remove, up, down].forEach { content.addSubview($0) }

        window.contentView = content
        tableView.reloadData()
    }

    private func button(_ title: String, _ action: Selector, x: CGFloat) -> NSButton {
        let b = NSButton(frame: NSRect(x: x, y: 12, width: title.count > 7 ? 92 : 80, height: 28))
        b.title = title
        b.bezelStyle = .rounded
        b.target = self
        b.action = action
        return b
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { sources.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField()
            f.identifier = id
            f.isBordered = false
            f.drawsBackground = false
            f.delegate = self
            return f
        }()
        let source = sources[row]
        field.stringValue = (id == Self.nameColumn) ? source.name : source.urlTemplate
        return field
    }

    // MARK: - Editing

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard sources.indices.contains(row), let id = field.identifier else { return }

        if id == Self.nameColumn {
            sources[row].name = field.stringValue
        } else {
            let template = field.stringValue
            guard URLBuilder.isValidTemplate(template) else {
                alert("URL template must contain the {q} placeholder.")
                field.stringValue = sources[row].urlTemplate // revert
                return
            }
            sources[row].urlTemplate = template
        }
        store.replaceAll(sources)
    }

    // MARK: - Actions

    @objc private func addSource() {
        sources.append(Source(name: "New Source", urlTemplate: "https://example.com/search?q={q}"))
        store.replaceAll(sources)
        tableView.reloadData()
        let row = sources.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeSource() {
        let row = tableView.selectedRow
        guard sources.indices.contains(row) else { return }
        sources.remove(at: row)
        store.replaceAll(sources)
        tableView.reloadData()
    }

    @objc private func moveUp() { move(by: -1) }
    @objc private func moveDown() { move(by: 1) }

    private func move(by offset: Int) {
        let row = tableView.selectedRow
        let target = row + offset
        guard sources.indices.contains(row), sources.indices.contains(target) else { return }
        sources.swapAt(row, target)
        store.replaceAll(sources)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
    }

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = message
        a.alertStyle = .warning
        a.runModal()
    }
}
