import SwiftUI
import UIKit

/// Invisible UIKit responder used to forward a physical keyboard to libretro.
struct HardwareKeyboardCapture: UIViewRepresentable {
    let isEnabled: Bool
    let onKey: (UInt, Bool) -> Void

    func makeUIView(context: Context) -> KeyboardResponderView {
        let view = KeyboardResponderView()
        view.onKey = onKey
        view.captureEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: KeyboardResponderView, context: Context) {
        uiView.onKey = onKey
        uiView.captureEnabled = isEnabled
        uiView.requestFocus()
    }
}

final class KeyboardResponderView: UIView {
    var onKey: ((UInt, Bool) -> Void)?

    var captureEnabled = false {
        didSet {
            if captureEnabled {
                requestFocus()
            } else {
                releaseAllKeys()
                resignFirstResponder()
            }
        }
    }

    private var pressedUsages: [Int: UInt] = [:]

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
        for press in presses {
            guard let key = press.key else { continue }
            let usage = Int(key.keyCode.rawValue)
            guard pressedUsages[usage] == nil,
                  let retroCode = Self.retroKeyCode(forHIDUsage: usage) else { continue }

            pressedUsages[usage] = retroCode
            onKey?(retroCode, true)
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
            guard let retroCode = pressedUsages.removeValue(forKey: usage) else { continue }

            onKey?(retroCode, false)
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
            if let retroCode = pressedUsages.removeValue(forKey: usage) {
                onKey?(retroCode, false)
            }
        }
        super.pressesCancelled(presses, with: event)
    }

    private func releaseAllKeys() {
        let codes = Array(pressedUsages.values)
        pressedUsages.removeAll()
        codes.forEach { onKey?($0, false) }
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
