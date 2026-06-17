import Carbon.HIToolbox

/// Registers a global hotkey via Carbon's `RegisterEventHotKey`, which fires
/// regardless of which app is frontmost and does not require Accessibility.
///
/// Matching is on raw key code + modifier flags, so option-letter dead keys
/// (⌥D → ∂) work — we never look at the produced character.
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    private let myID: UInt32

    private static var registry: [UInt32: HotKeyMonitor] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        self.myID = HotKeyMonitor.nextID
        HotKeyMonitor.nextID += 1

        HotKeyMonitor.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x5152_4b59 /* 'QRKY' */), id: myID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        hotKeyRef = ref
        HotKeyMonitor.registry[myID] = self
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        HotKeyMonitor.registry[myID] = nil
    }

    fileprivate func fire() { callback() }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                HotKeyMonitor.registry[hkID.id]?.fire()
                return noErr
            },
            1, &spec, nil, nil
        )
    }
}
