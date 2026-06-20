import AppKit
import QuickRunKit
import QuickRunUI

/// "Add from Library" sheet: a category sidebar on the left, the chosen
/// category's catalog entries as a checklist on the right. Selection spans
/// category switches; entries already present in the user's Sources (matched by
/// urlTemplate) show as added and can't be re-selected. "Add" hands the freshly
/// minted Sources back through `onAdd` and dismisses. Throwaway-free: the dedup /
/// minting all lives in `SourceLibrary` (QuickRunKit); this is just the shell.
final class SourceLibraryPickerController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let existing: [Source]
    private let onAdd: ([Source]) -> Void

    private let window: NSWindow
    private let categoryTable = NSTableView()
    private let entryTable = NSTableView()
    private let addButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")

    private let categories = SourceLibrary.categories
    private var currentCategory: String
    private var selected = Set<String>() // keyed by urlTemplate — the dedup key

    private static let categoryColumn = NSUserInterfaceItemIdentifier("category")
    private static let checkColumn = NSUserInterfaceItemIdentifier("check")
    private static let entryNameColumn = NSUserInterfaceItemIdentifier("entryName")

    init(existing: [Source], onAdd: @escaping ([Source]) -> Void) {
        self.existing = existing
        self.onAdd = onAdd
        self.currentCategory = categories.first ?? ""
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Source Library"
        buildUI()
    }

    /// Present as a sheet on `parent`. The caller must retain this controller for
    /// the lifetime of the sheet.
    func present(in parent: NSWindow) {
        categoryTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        entryTable.reloadData()
        updateAddButton()
        parent.beginSheet(window)
    }

    // MARK: - UI

    private func buildUI() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 440))

        let header = NSTextField(labelWithString: "Add Sources from the library")
        header.font = .quickRunSerif(ofSize: 15, weight: .semibold)
        header.frame = NSRect(x: 20, y: 404, width: 540, height: 22)
        content.addSubview(header)

        let caption = NSTextField(labelWithString: "Pick across categories, then add them all at once. Already-added Sources are dimmed.")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 20, y: 384, width: 540, height: 16)
        content.addSubview(caption)

        // Category sidebar
        let catCol = NSTableColumn(identifier: Self.categoryColumn)
        catCol.width = 132
        categoryTable.addTableColumn(catCol)
        categoryTable.headerView = nil
        categoryTable.style = .sourceList
        categoryTable.rowHeight = 26
        categoryTable.dataSource = self
        categoryTable.delegate = self
        content.addSubview(scrollBox(categoryTable, frame: NSRect(x: 20, y: 64, width: 150, height: 312)))

        // Entry checklist
        let checkCol = NSTableColumn(identifier: Self.checkColumn)
        checkCol.width = 26
        let nameCol = NSTableColumn(identifier: Self.entryNameColumn)
        nameCol.width = 330
        entryTable.addTableColumn(checkCol)
        entryTable.addTableColumn(nameCol)
        entryTable.headerView = nil
        entryTable.rowHeight = 28
        entryTable.dataSource = self
        entryTable.delegate = self
        content.addSubview(scrollBox(entryTable, frame: NSRect(x: 180, y: 64, width: 380, height: 312)))

        // Footer
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 20, y: 20, width: 240, height: 20)
        content.addSubview(countLabel)

        let cancel = NSButton()
        cancel.title = "Cancel"
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 372, y: 14, width: 90, height: 30)
        cancel.target = self
        cancel.action = #selector(cancelSheet)
        content.addSubview(cancel)

        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.frame = NSRect(x: 466, y: 14, width: 94, height: 30)
        addButton.target = self
        addButton.action = #selector(addSelected)
        content.addSubview(addButton)

        window.contentView = content
    }

    private func scrollBox(_ table: NSTableView, frame: NSRect) -> NSScrollView {
        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        return scroll
    }

    private func entries() -> [CatalogEntry] {
        SourceLibrary.entries(in: currentCategory)
    }

    private func updateAddButton() {
        countLabel.stringValue = selected.isEmpty ? "Nothing selected" : "\(selected.count) selected"
        addButton.title = selected.isEmpty ? "Add" : "Add \(selected.count)"
        addButton.isEnabled = !selected.isEmpty
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === categoryTable ? categories.count : entries().count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === categoryTable {
            let label = (tableView.makeView(withIdentifier: Self.categoryColumn, owner: self) as? NSTextField) ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = Self.categoryColumn
                f.font = .systemFont(ofSize: 13)
                return f
            }()
            label.stringValue = categories[row]
            return label
        }

        let entry = entries()[row]
        let present = SourceLibrary.isPresent(entry, in: existing)

        if tableColumn?.identifier == Self.checkColumn {
            let check = (tableView.makeView(withIdentifier: Self.checkColumn, owner: self) as? NSButton) ?? {
                let b = NSButton()
                b.identifier = Self.checkColumn
                b.setButtonType(.switch)
                b.title = ""
                b.target = self
                b.action = #selector(toggleCheck(_:))
                return b
            }()
            check.state = (present || selected.contains(entry.urlTemplate)) ? .on : .off
            check.isEnabled = !present
            return check
        }

        let field = (tableView.makeView(withIdentifier: Self.entryNameColumn, owner: self) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = Self.entryNameColumn
            f.font = .systemFont(ofSize: 13)
            return f
        }()
        field.stringValue = present ? "\(entry.name)  (added)" : entry.name
        field.textColor = present ? .tertiaryLabelColor : .labelColor
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === categoryTable else { return }
        let row = categoryTable.selectedRow
        guard categories.indices.contains(row) else { return }
        currentCategory = categories[row]
        entryTable.reloadData()
    }

    // MARK: - Actions

    @objc private func toggleCheck(_ sender: NSButton) {
        toggleEntry(at: entryTable.row(for: sender))
    }

    private func toggleEntry(at row: Int) {
        let list = entries()
        guard list.indices.contains(row) else { return }
        let entry = list[row]
        guard !SourceLibrary.isPresent(entry, in: existing) else { return }
        if selected.contains(entry.urlTemplate) {
            selected.remove(entry.urlTemplate)
        } else {
            selected.insert(entry.urlTemplate)
        }
        entryTable.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        updateAddButton()
    }

    @objc private func addSelected() {
        // Preserve catalog order across categories, dedup against existing.
        let chosen = SourceLibrary.catalog.filter { selected.contains($0.urlTemplate) }
        let minted = SourceLibrary.newSources(for: chosen, existing: existing)
        if !minted.isEmpty { onAdd(minted) }
        dismiss()
    }

    @objc private func cancelSheet() {
        dismiss()
    }

    private func dismiss() {
        window.sheetParent?.endSheet(window)
    }
}
