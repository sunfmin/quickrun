import AppKit
import QuickRunKit

/// Settings window: a table of Sources (name + URL template) with add / remove /
/// move, persisted through the SourceStore. A URL template missing the `{q}`
/// placeholder is rejected on commit.
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store: UserDefaultsSourceStore
    private let hotkeyStore: HotkeyStore
    private let saveLocationStore: SaveLocationStore
    private let defaultHotkey: Hotkey
    private let onHotkeyChanged: () -> Void
    private var sources: [Source]
    private let window: NSWindow
    private let tableView = NSTableView()
    private let hotkeyButton = NSButton()
    private let grantButton = NSButton()
    private var recordMonitor: Any?
    private var libraryPicker: SourceLibraryPickerController?
    private let permissionLabel = NSTextField(labelWithString: "")
    private let saveLocationLabel = NSTextField(labelWithString: "")

    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let urlColumn = NSUserInterfaceItemIdentifier("url")

    init(
        store: UserDefaultsSourceStore,
        hotkeyStore: HotkeyStore,
        saveLocationStore: SaveLocationStore,
        defaultHotkey: Hotkey,
        onHotkeyChanged: @escaping () -> Void
    ) {
        self.store = store
        self.hotkeyStore = hotkeyStore
        self.saveLocationStore = saveLocationStore
        self.defaultHotkey = defaultHotkey
        self.onHotkeyChanged = onHotkeyChanged
        self.sources = store.load()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "QuickRun Settings"
        window.titlebarSeparatorStyle = .line
        window.isReleasedWhenClosed = false
        buildUI()
    }

    func show() {
        sources = store.load()
        tableView.reloadData()
        updatePermissionStatus()
        updateSaveLocationLabel()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func buildUI() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 520))
        content.autoresizingMask = [.width, .height]

        // ── General ──────────────────────────────────────────────────────────
        content.addSubview(sectionHeader("General", y: 480))

        let hotkeyLabel = NSTextField(labelWithString: "Global hotkey")
        hotkeyLabel.font = .systemFont(ofSize: 13)
        hotkeyLabel.frame = NSRect(x: 20, y: 448, width: 110, height: 22)
        hotkeyLabel.autoresizingMask = [.minYMargin]
        content.addSubview(hotkeyLabel)

        hotkeyButton.frame = NSRect(x: 140, y: 444, width: 170, height: 26)
        hotkeyButton.autoresizingMask = [.minYMargin]
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.target = self
        hotkeyButton.action = #selector(recordHotkey)
        updateHotkeyButtonTitle()
        content.addSubview(hotkeyButton)

        content.addSubview(caption("Click, then press the new combination.", x: 142, y: 424, width: 420))

        let accessibilityLabel = NSTextField(labelWithString: "Accessibility")
        accessibilityLabel.font = .systemFont(ofSize: 13)
        accessibilityLabel.frame = NSRect(x: 20, y: 392, width: 110, height: 22)
        accessibilityLabel.autoresizingMask = [.minYMargin]
        content.addSubview(accessibilityLabel)

        permissionLabel.frame = NSRect(x: 142, y: 392, width: 210, height: 22)
        permissionLabel.autoresizingMask = [.minYMargin]
        content.addSubview(permissionLabel)

        grantButton.frame = NSRect(x: 370, y: 390, width: 210, height: 26)
        grantButton.title = "Open Accessibility Settings"
        grantButton.bezelStyle = .rounded
        grantButton.autoresizingMask = [.minYMargin, .minXMargin]
        grantButton.target = self
        grantButton.action = #selector(openPermissionPane)
        content.addSubview(grantButton)
        updatePermissionStatus()

        let saveLabel = NSTextField(labelWithString: "Save screenshots to")
        saveLabel.font = .systemFont(ofSize: 13)
        saveLabel.frame = NSRect(x: 20, y: 356, width: 150, height: 22)
        saveLabel.autoresizingMask = [.minYMargin]
        content.addSubview(saveLabel)

        saveLocationLabel.font = .systemFont(ofSize: 12)
        saveLocationLabel.textColor = .secondaryLabelColor
        saveLocationLabel.lineBreakMode = .byTruncatingMiddle
        saveLocationLabel.frame = NSRect(x: 176, y: 357, width: 250, height: 20)
        saveLocationLabel.autoresizingMask = [.minYMargin]
        content.addSubview(saveLocationLabel)

        let chooseButton = NSButton()
        chooseButton.title = "Choose…"
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 446, y: 354, width: 134, height: 26)
        chooseButton.autoresizingMask = [.minYMargin, .minXMargin]
        chooseButton.target = self
        chooseButton.action = #selector(chooseSaveLocation)
        content.addSubview(chooseButton)
        updateSaveLocationLabel()

        let divider = DynamicLayerView(frame: NSRect(x: 20, y: 336, width: 560, height: 1))
        divider.fillColor = .separatorColor
        divider.autoresizingMask = [.width, .minYMargin]
        content.addSubview(divider)

        // ── Sources ──────────────────────────────────────────────────────────
        content.addSubview(sectionHeader("Sources", y: 304))
        content.addSubview(caption("Each Source opens in its own tab. {q} is replaced with your selection.", x: 20, y: 282, width: 560))

        let listBox = DynamicLayerView(frame: NSRect(x: 20, y: 54, width: 560, height: 216))
        listBox.cornerRadius = 8
        listBox.borderWidth = 1
        listBox.borderColor = .separatorColor
        listBox.fillColor = .textBackgroundColor
        listBox.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: listBox.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let nameCol = NSTableColumn(identifier: Self.nameColumn)
        nameCol.title = "Name"
        nameCol.width = 150
        let urlCol = NSTableColumn(identifier: Self.urlColumn)
        urlCol.title = "URL template"
        urlCol.width = 390
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(urlCol)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
        scroll.documentView = tableView
        listBox.addSubview(scroll)
        content.addSubview(listBox)

        let toolbar = NSSegmentedControl()
        toolbar.segmentStyle = .smallSquare
        toolbar.trackingMode = .momentary
        toolbar.segmentCount = 4
        let segments: [(symbol: String, tip: String)] = [
            ("plus", "Add a Source"),
            ("minus", "Remove the selected Source"),
            ("chevron.up", "Move up"),
            ("chevron.down", "Move down"),
        ]
        for (i, segment) in segments.enumerated() {
            toolbar.setImage(NSImage(systemSymbolName: segment.symbol, accessibilityDescription: segment.tip), forSegment: i)
            toolbar.setWidth(34, forSegment: i)
            toolbar.setToolTip(segment.tip, forSegment: i)
        }
        toolbar.target = self
        toolbar.action = #selector(toolbarAction)
        toolbar.frame = NSRect(x: 20, y: 18, width: 136, height: 26)
        toolbar.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(toolbar)

        let libraryButton = NSButton()
        libraryButton.title = "Add from Library…"
        libraryButton.bezelStyle = .rounded
        libraryButton.frame = NSRect(x: 164, y: 16, width: 160, height: 28)
        libraryButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        libraryButton.target = self
        libraryButton.action = #selector(openLibrary)
        content.addSubview(libraryButton)

        window.contentView = content
        tableView.reloadData()
    }

    private func sectionHeader(_ title: String, y: CGFloat) -> NSTextField {
        let header = NSTextField(labelWithString: title)
        header.font = .quickRunSerif(ofSize: 15, weight: .semibold)
        header.textColor = .labelColor
        header.frame = NSRect(x: 20, y: y, width: 300, height: 22)
        header.autoresizingMask = [.minYMargin]
        return header
    }

    private func caption(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: x, y: y, width: width, height: 16)
        label.autoresizingMask = [.minYMargin]
        return label
    }

    @objc private func toolbarAction(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: addSource()
        case 1: removeSource()
        case 2: moveUp()
        case 3: moveDown()
        default: break
        }
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { sources.count }

    /// A bottom hairline drawn only on populated rows, so the empty list area
    /// below the last Source stays clean instead of showing phantom row lines.
    private final class SourceRowView: NSTableRowView {
        override func drawSeparator(in dirtyRect: NSRect) {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("SourceRow")
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? SourceRowView { return reused }
        let view = SourceRowView()
        view.identifier = id
        return view
    }

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

    @objc private func openLibrary() {
        let picker = SourceLibraryPickerController(existing: sources) { [weak self] minted in
            guard let self, !minted.isEmpty else { return }
            self.sources.append(contentsOf: minted)
            self.store.replaceAll(self.sources)
            self.tableView.reloadData()
            let last = self.sources.count - 1
            self.tableView.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
            self.tableView.scrollRowToVisible(last)
        }
        libraryPicker = picker
        picker.present(in: window)
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

    // MARK: - Permission

    private func updatePermissionStatus() {
        let granted = AccessibilityPermission.isGranted
        permissionLabel.stringValue = granted ? "Granted ✓" : "Not granted — required"
        permissionLabel.textColor = granted ? .secondaryLabelColor : .systemRed
        grantButton.isHidden = granted
    }

    @objc private func openPermissionPane() {
        AccessibilityPermission.openSettingsPane()
    }

    // MARK: - Save location

    private func updateSaveLocationLabel() {
        let path = saveLocationStore.folder().path
        saveLocationLabel.stringValue = (path as NSString).abbreviatingWithTildeInPath
    }

    @objc private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveLocationStore.folder()
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            saveLocationStore.setFolder(url)
            updateSaveLocationLabel()
        }
    }

    // MARK: - Hotkey recorder

    private func updateHotkeyButtonTitle() {
        let hotkey = hotkeyStore.load() ?? defaultHotkey
        hotkeyButton.title = HotkeyFormatter.display(hotkey)
    }

    @objc private func recordHotkey() {
        hotkeyButton.attributedTitle = NSAttributedString(string: "Press keys…", attributes: [
            .foregroundColor: Palette.accent,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        ])
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Require at least one modifier so we don't bind a bare key globally.
            let needed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard !event.modifierFlags.intersection(needed).isEmpty else { return nil }

            self.hotkeyStore.save(HotkeyFormatter.hotkey(from: event))
            self.updateHotkeyButtonTitle()
            if let monitor = self.recordMonitor {
                NSEvent.removeMonitor(monitor)
                self.recordMonitor = nil
            }
            self.onHotkeyChanged()
            return nil
        }
    }

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = message
        a.alertStyle = .warning
        a.runModal()
    }
}
