import AppKit
import Carbon.HIToolbox
import QuickRunKit

/// Renders a `Hotkey` as a glyph string (e.g. "⌥D") and converts an NSEvent
/// into a `Hotkey` for the recorder.
enum HotkeyFormatter {
    /// Carbon modifier glyphs in display order.
    private static let modifierGlyphs: [(mask: Int, glyph: String)] = [
        (controlKey, "⌃"),
        (optionKey, "⌥"),
        (shiftKey, "⇧"),
        (cmdKey, "⌘"),
    ]

    private static let keyLabels: [UInt32: String] = {
        var map: [UInt32: String] = [
            UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
            UInt32(kVK_Escape): "⎋",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        for (code, label) in letters { map[UInt32(code)] = label }
        return map
    }()

    static func display(_ hotkey: Hotkey) -> String {
        let mods = modifierGlyphs
            .filter { hotkey.modifiers & UInt32($0.mask) != 0 }
            .map(\.glyph)
            .joined()
        let key = keyLabels[hotkey.keyCode] ?? "key \(hotkey.keyCode)"
        return mods + key
    }

    /// Build a `Hotkey` from a key-down event, translating Cocoa modifier flags
    /// to the Carbon mask used by `RegisterEventHotKey`.
    static func hotkey(from event: NSEvent) -> Hotkey {
        var carbon: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }
}
