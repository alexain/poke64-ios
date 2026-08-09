import SwiftUI
import UIKit

/// Invisible UIKit responder used to forward a physical keyboard to libretro.
struct HardwareKeyboardCapture: UIViewRepresentable {
    let isEnabled: Bool
    let mappingMode: C64PhysicalKeyboardMode
    let onKey: (UInt, Bool) -> Void
    let onShiftedKey: (UInt, UInt, Bool) -> Void

    func makeUIView(context: Context) -> KeyboardResponderView {
        let view = KeyboardResponderView()
        view.onKey = onKey
        view.onShiftedKey = onShiftedKey
        view.mappingMode = mappingMode
        view.captureEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: KeyboardResponderView, context: Context) {
        uiView.onKey = onKey
        uiView.onShiftedKey = onShiftedKey
        if uiView.mappingMode != mappingMode {
            uiView.releaseAllKeys()
            uiView.mappingMode = mappingMode
        }
        uiView.captureEnabled = isEnabled
    }
}

final class KeyboardResponderView: UIView {
    var onKey: ((UInt, Bool) -> Void)?
    var onShiftedKey: ((UInt, UInt, Bool) -> Void)?
    var mappingMode: C64PhysicalKeyboardMode = .defaultValue

    var captureEnabled = false {
        didSet {
            guard captureEnabled != oldValue else { return }

            if captureEnabled {
                requestFocus()
            } else {
                releaseAllKeys()
                resignFirstResponder()
            }
        }
    }

    private lazy var hiddenInputView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }()

    /// HID usage -> the libretro key sequence generated for that physical key.
    /// Host-layout mode may synthesize C64 Shift plus a base key for a single
    /// host character, so releases must mirror the exact sequence.
    private var pressedUsages: [Int: [UInt]] = [:]
    private var activeCodeCounts: [UInt: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationDidBecomeActive() {
        requestFocus()
    }

    @objc private func applicationWillResignActive() {
        releaseAllKeys()
    }

    override var canBecomeFirstResponder: Bool { true }

    /// Keep physical-keyboard capture active without asking iPadOS to show
    /// its software keyboard when SwiftUI menus update the responder chain.
    override var inputView: UIView? { hiddenInputView }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestFocus()
    }

    /// The responder must receive keyboard events without intercepting touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func requestFocus() {
        guard captureEnabled, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureEnabled, self.window != nil else { return }
            _ = self.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        // Host-layout mode reserves Control and the right Option key as real
        // C64 modifiers. Process those modifier presses first so combinations
        // such as C=+R or CTRL+letter reach VICE in the expected order.
        let c64ModifierUsages: Set<Int> = [0xE0, 0xE4, 0xE6]
        let incomingUsages = Set(presses.compactMap { press in
            press.key.map { Int($0.keyCode.rawValue) }
        })
        let c64ModifierHeld = mappingMode == .hostLayout
            && (!c64ModifierUsages.isDisjoint(with: Set(pressedUsages.keys))
                || !c64ModifierUsages.isDisjoint(with: incomingUsages))
        let orderedPresses = presses.sorted { lhs, rhs in
            let leftUsage = lhs.key.map { Int($0.keyCode.rawValue) } ?? Int.max
            let rightUsage = rhs.key.map { Int($0.keyCode.rawValue) } ?? Int.max
            let leftPriority = c64ModifierUsages.contains(leftUsage) ? 0 : 1
            let rightPriority = c64ModifierUsages.contains(rightUsage) ? 0 : 1
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return leftUsage < rightUsage
        }

        for press in orderedPresses {
            guard let key = press.key else { continue }
            let usage = Int(key.keyCode.rawValue)
            guard pressedUsages[usage] == nil,
                  let codes = Self.retroKeyCodes(
                    for: key,
                    hidUsage: usage,
                    mappingMode: mappingMode,
                    c64ModifierHeld: c64ModifierHeld && !c64ModifierUsages.contains(usage)
                  ) else { continue }

            pressedUsages[usage] = codes
            pressCodes(codes)
            handled = true
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let usage = Int(key.keyCode.rawValue)
            guard let codes = pressedUsages.removeValue(forKey: usage) else { continue }

            releaseCodes(codes)
            handled = true
        }

        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            let usage = Int(key.keyCode.rawValue)
            if let codes = pressedUsages.removeValue(forKey: usage) {
                releaseCodes(codes)
            }
        }
        super.pressesCancelled(presses, with: event)
    }

    private static func shiftedChord(_ codes: [UInt]) -> (modifier: UInt, base: UInt)? {
        guard codes.count == 2, codes[0] == 303 || codes[0] == 304 else { return nil }
        return (codes[0], codes[1])
    }

    private func pressCodes(_ codes: [UInt]) {
        if let chord = Self.shiftedChord(codes), let onShiftedKey {
            for code in codes {
                activeCodeCounts[code, default: 0] += 1
            }
            // VICE/libretro scans retro key codes in numeric order. If Shift and
            // the base key arrive in the same frame, the base key (for example
            // `3` or `,`) is processed first and can leak through before Shift.
            // Ask the session to stage the modifier one emulated frame earlier.
            onShiftedKey(chord.modifier, chord.base, true)
            return
        }

        for code in codes {
            let count = activeCodeCounts[code, default: 0]
            activeCodeCounts[code] = count + 1
            if count == 0 {
                onKey?(code, true)
            }
        }
    }

    private func releaseCodes(_ codes: [UInt]) {
        if let chord = Self.shiftedChord(codes), let onShiftedKey {
            for code in codes.reversed() {
                guard let count = activeCodeCounts[code] else { continue }
                if count <= 1 {
                    activeCodeCounts.removeValue(forKey: code)
                } else {
                    activeCodeCounts[code] = count - 1
                }
            }
            onShiftedKey(chord.modifier, chord.base, false)
            return
        }

        for code in codes.reversed() {
            guard let count = activeCodeCounts[code] else { continue }
            if count <= 1 {
                activeCodeCounts.removeValue(forKey: code)
                onKey?(code, false)
            } else {
                activeCodeCounts[code] = count - 1
            }
        }
    }

    func releaseAllKeys() {
        let sequences = Array(pressedUsages.values)
        pressedUsages.removeAll()
        sequences.forEach { releaseCodes($0) }

        // Defensive cleanup for any state not represented by pressedUsages.
        let leftovers = Array(activeCodeCounts.keys)
        activeCodeCounts.removeAll()
        leftovers.forEach { onKey?($0, false) }
    }

    private static func retroKeyCodes(
        for key: UIKey,
        hidUsage usage: Int,
        mappingMode: C64PhysicalKeyboardMode,
        c64ModifierHeld: Bool = false
    ) -> [UInt]? {
        guard mappingMode == .hostLayout else {
            guard let code = retroKeyCode(forHIDUsage: usage) else { return nil }
            return [code]
        }

        if let special = hostLayoutSpecialKeyCodes(forHIDUsage: usage) {
            return special
        }

        // In host-layout mode iPadOS resolves Shift/AltGr and the active host
        // keyboard layout first. POKE64 then translates the resulting printable
        // character back to the positional libretro codes used by the C64
        // virtual keyboard. Keeping VICE itself positional is intentional: the
        // on-screen C64 keyboard must never change when the host preference does.
        var characters = c64ModifierHeld ? key.charactersIgnoringModifiers : key.characters

        // On some iPad hardware-keyboard combinations the translated character
        // can briefly be reported without Shift even though modifierFlags already
        // contains it. The Italian layout places `=` on Shift+0, so preserve that
        // common host-layout case instead of intermittently emitting `0`.
        if key.modifierFlags.contains(.shift),
           characters == key.charactersIgnoringModifiers,
           characters == "0",
           Locale.current.identifier.lowercased().hasPrefix("it") {
            characters = "="
        }

        guard characters.unicodeScalars.count == 1,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }
        return c64TextKeyCodes(for: scalar)
    }

    /// Host-layout mode is text-oriented. Shift and Alt/AltGr are consumed by
    /// iPadOS to produce the printed host character instead of being forwarded
    /// as C64 modifiers. Use positional mode when exact C64 modifier/graphics
    /// behavior is required.
    private static func hostLayoutSpecialKeyCodes(forHIDUsage usage: Int) -> [UInt]? {
        switch usage {
        case 0x28: return [13]  // Return
        case 0x29: return [27]  // Escape / RUN-STOP
        case 0x2A: return [8]   // Backspace / DEL
        case 0x2B: return [9]   // Tab / C64 CTRL
        case 0x39: return [301] // Caps Lock / SHIFT LOCK

        case 0x3A...0x41: // F1...F8
            return [UInt(282 + usage - 0x3A)]
        case 0x42...0x45: // F9...F12: preserve existing mapping
            return [UInt(282 + usage - 0x3A)]

        case 0x46: return [316] // Print Screen
        case 0x47: return [302] // Scroll Lock
        case 0x48: return [19]  // Pause
        case 0x49: return [277] // Insert
        case 0x4A: return [278] // Home / CLR-HOME
        case 0x4B: return [280] // Page Up / RESTORE
        case 0x4C: return [127] // Forward Delete
        case 0x4D: return [277] // End alias -> C64 £ (RETROK_INSERT in positional map)
        case 0x4E: return [92]  // Page Down alias -> C64 = (RETROK_BACKSLASH in positional map)
        case 0x4F: return [275] // Right
        case 0x50: return [276] // Left
        case 0x51: return [274] // Down
        case 0x52: return [273] // Up

        case 0x53: return [300] // Num Lock
        case 0x54: return [267] // Keypad /
        case 0x55: return [268] // Keypad *
        case 0x56: return [269] // Keypad -
        case 0x57: return [270] // Keypad +
        case 0x58: return [271] // Keypad Enter
        case 0x59...0x61: return [UInt(257 + usage - 0x59)]
        case 0x62: return [256] // Keypad 0
        case 0x63: return [266] // Keypad period

        case 0xE0, 0xE4: return [9]   // Control -> C64 CTRL
        case 0xE6: return [306]       // Right Option -> C64 Commodore (C=)
        case 0xE1, 0xE2, 0xE3, 0xE5, 0xE7:
            return []                 // Shift / left Option / Command stay host modifiers

        default:
            return nil
        }
    }

    private static func c64TextKeyCodes(for scalar: UnicodeScalar) -> [UInt]? {
        let value = scalar.value

        // Letters are text in host-layout mode. Uppercase host input does not
        // become C64 Shift+letter graphics; positional mode remains available
        // for exact matrix-oriented typing.
        if value >= 65 && value <= 90 {
            return [UInt(value + 32)]
        }
        if value >= 97 && value <= 122 {
            return [UInt(value)]
        }
        if value >= 48 && value <= 57 {
            return [UInt(value)]
        }

        let rightShift: UInt = 303
        switch scalar {
        case " ": return [32]
        case "+": return [45]       // C64 +
        case "-", "−": return [61]  // C64 -
        case "=": return [92]       // C64 = in VICE positional keymap
        case "@": return [91]
        case "*": return [93]
        case ":": return [59]
        case ";": return [39]
        case ",": return [44]
        case ".": return [46]
        case "/": return [47]
        case "£": return [277]      // C64 £ in VICE positional keymap
        case "←": return [96]
        case "↑": return [92]

        case "!": return [rightShift, 49]
        case "\"": return [rightShift, 50]
        case "#": return [rightShift, 51]
        case "$": return [rightShift, 52]
        case "%": return [rightShift, 53]
        case "&": return [rightShift, 54]
        case "'": return [rightShift, 55]
        case "(": return [rightShift, 56]
        case ")": return [rightShift, 57]
        case "[": return [rightShift, 59]
        case "]": return [rightShift, 39]
        case "<": return [rightShift, 44]
        case ">": return [rightShift, 46]
        case "?": return [rightShift, 47]
        case "π": return [rightShift, 92]

        // Useful fallbacks for the standard Italian PC layout. AltGr/Shift
        // combinations that actually produce @, #, [, ], etc. are handled by
        // the generic cases above; these two mirror VICE's Italian symbolic map
        // for the unmodified accented keys most commonly used around L/Return.
        case "ò", "Ò": return [91]                // Italian ò key -> C64 @
        case "à", "À": return [rightShift, 51]    // Italian à key -> C64 #

        default:
            return nil
        }
    }

    /// USB HID usage -> libretro `retro_key` value.
    /// Raw HID values avoid source-level dependencies on SDK-specific enum case names.
    private static func retroKeyCode(forHIDUsage usage: Int) -> UInt? {
        switch usage {
        case 0x04...0x1D: // A...Z
            return UInt(97 + usage - 0x04)

        case 0x1E...0x26: // 1...9
            return UInt(49 + usage - 0x1E)
        case 0x27: return 48 // 0

        case 0x28: return 13  // Return
        case 0x29: return 27  // Escape / RUN-STOP
        case 0x2A: return 8   // Backspace / DEL
        case 0x2B: return 9   // Tab / C64 CTRL
        case 0x2C: return 32  // Space
        case 0x2D: return 45  // - (maps to C64 +)
        case 0x2E: return 61  // = (maps to C64 -)
        case 0x2F: return 91  // [ (maps to C64 @)
        case 0x30: return 93  // ] (maps to C64 *)
        case 0x31: return 92  // Backslash (maps to C64 up arrow)
        case 0x32: return 323 // Non-US # / OEM 102
        case 0x33: return 59  // ; (maps to C64 :)
        case 0x34: return 39  // ' (maps to C64 ;)
        case 0x35: return 96  // ` (maps to C64 left arrow)
        case 0x36: return 44  // ,
        case 0x37: return 46  // .
        case 0x38: return 47  // /
        case 0x39: return 301 // Caps Lock / SHIFT LOCK

        case 0x3A...0x45: // F1...F12
            return UInt(282 + usage - 0x3A)

        case 0x46: return 316 // Print Screen
        case 0x47: return 302 // Scroll Lock
        case 0x48: return 19  // Pause
        case 0x49: return 277 // Insert
        case 0x4A: return 278 // Home / CLR-HOME
        case 0x4B: return 280 // Page Up / RESTORE
        case 0x4C: return 127 // Forward Delete
        case 0x4D: return 279 // End / £
        case 0x4E: return 281 // Page Down / =
        case 0x4F: return 275 // Right
        case 0x50: return 276 // Left
        case 0x51: return 274 // Down
        case 0x52: return 273 // Up

        case 0x53: return 300 // Num Lock
        case 0x54: return 267 // Keypad /
        case 0x55: return 268 // Keypad *
        case 0x56: return 269 // Keypad -
        case 0x57: return 270 // Keypad +
        case 0x58: return 271 // Keypad Enter
        case 0x59...0x61: // Keypad 1...9
            return UInt(257 + usage - 0x59)
        case 0x62: return 256 // Keypad 0
        case 0x63: return 266 // Keypad period
        case 0x64: return 323 // Non-US backslash / OEM 102

        case 0xE0: return 306 // Left Control -> C64 Commodore
        case 0xE1: return 304 // Left Shift
        case 0xE2: return 308 // Left Alt
        case 0xE3: return 310 // Left GUI / Command
        case 0xE4: return 305 // Right Control (core joyport shortcut)
        case 0xE5: return 303 // Right Shift
        case 0xE6: return 307 // Right Alt / AltGr
        case 0xE7: return 309 // Right GUI / Command

        default:
            return nil
        }
    }
}
