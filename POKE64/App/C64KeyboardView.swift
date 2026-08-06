import SwiftUI

enum C64KeyboardMode: String, CaseIterable, Identifiable {
    case compact
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .full:
            return "Full"
        }
    }

    fileprivate var keyHeight: CGFloat {
        switch self {
        case .compact:
            return 34
        case .full:
            return 48
        }
    }

    fileprivate var keySpacing: CGFloat {
        switch self {
        case .compact:
            return 3
        case .full:
            return 5
        }
    }

    fileprivate var rowSpacing: CGFloat {
        switch self {
        case .compact:
            return 4
        case .full:
            return 6
        }
    }

    fileprivate var keyFontSize: CGFloat {
        switch self {
        case .compact:
            return 9
        case .full:
            return 11
        }
    }

    fileprivate var panelHeight: CGFloat {
        switch self {
        case .compact:
            return 250
        case .full:
            return 326
        }
    }
}

struct C64KeyboardView: View {
    @EnvironmentObject private var emulator: EmulatorModel

    @Binding var mode: C64KeyboardMode
    @Binding var shiftLockIsActive: Bool
    let onHide: () -> Void

    @State private var pressedShiftCodes: Set<UInt> = []
    @State private var commodoreIsPressed = false

    var body: some View {
        VStack(spacing: 0) {
            keyboardHeader

            Divider()
                .overlay(.white.opacity(0.10))

            GeometryReader { proxy in
                VStack(spacing: mode.rowSpacing) {
                    keyboardRow(Self.numberRow, availableWidth: proxy.size.width)
                    keyboardRow(Self.qwertyRow, availableWidth: proxy.size.width)
                    keyboardRow(Self.homeRow, availableWidth: proxy.size.width)
                    keyboardRow(Self.bottomRow, availableWidth: proxy.size.width)
                    keyboardRow(Self.spaceRow, availableWidth: proxy.size.width)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(height: mode.panelHeight)
        .background(Color.black.opacity(0.97))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commodore 64 keyboard")
        .onDisappear {
            releaseMomentaryModifiers()
        }
    }

    private var legendMode: C64KeyboardLegendMode {
        if commodoreIsPressed {
            return .commodore
        }
        if shiftLockIsActive || !pressedShiftCodes.isEmpty {
            return .shift
        }
        return .normal
    }

    private var keyboardHeader: some View {
        HStack(spacing: 12) {
            Label("C64 Keyboard", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            if legendMode != .normal {
                Text(legendMode.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(legendMode.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(legendMode.tint.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Active modifier: \(legendMode.title)")
            }

            Spacer(minLength: 12)

            Picker("Keyboard size", selection: $mode) {
                ForEach(C64KeyboardMode.allCases) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 176)

            Button {
                releaseMomentaryModifiers()
                onHide()
            } label: {
                Label("Hide", systemImage: "chevron.down")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func keyboardRow(
        _ keys: [C64VirtualKey],
        availableWidth: CGFloat
    ) -> some View {
        let totalUnits = keys.reduce(CGFloat.zero) { partialResult, key in
            partialResult + key.units
        }
        let spacingWidth = mode.keySpacing * CGFloat(max(0, keys.count - 1))
        let usableWidth = max(1, availableWidth - 20 - spacingWidth)
        let unitWidth = usableWidth / max(1, totalUnits)

        return HStack(spacing: mode.keySpacing) {
            ForEach(keys) { key in
                C64VirtualKeyButton(
                    key: key,
                    legendMode: legendMode,
                    isLatched: isLatched(key),
                    width: unitWidth * key.units,
                    height: mode.keyHeight,
                    fontSize: mode.keyFontSize
                ) { pressed in
                    handle(key, pressed: pressed)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func handle(_ key: C64VirtualKey, pressed: Bool) {
        switch key.role {
        case .shift:
            if pressed {
                pressedShiftCodes.insert(key.code)
            } else {
                pressedShiftCodes.remove(key.code)
            }
            emulator.setRawKey(key.code, pressed: pressed)

        case .commodore:
            commodoreIsPressed = pressed
            emulator.setRawKey(key.code, pressed: pressed)

        case .shiftLock:
            emulator.setRawKey(key.code, pressed: pressed)
            if pressed {
                shiftLockIsActive.toggle()
            }

        case .standard:
            emulator.setRawKey(key.code, pressed: pressed)
        }
    }

    private func releaseMomentaryModifiers() {
        for code in pressedShiftCodes {
            emulator.setRawKey(code, pressed: false)
        }
        pressedShiftCodes.removeAll()

        if commodoreIsPressed {
            emulator.setRawKey(Self.commodoreKeyCode, pressed: false)
            commodoreIsPressed = false
        }
    }

    private func isLatched(_ key: C64VirtualKey) -> Bool {
        switch key.role {
        case .shift:
            return pressedShiftCodes.contains(key.code)
        case .commodore:
            return commodoreIsPressed
        case .shiftLock:
            return shiftLockIsActive
        case .standard:
            return false
        }
    }
}

private enum C64KeyboardLegendMode: Equatable {
    case normal
    case shift
    case commodore

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .shift:
            return "SHIFT"
        case .commodore:
            return "C="
        }
    }

    var tint: Color {
        switch self {
        case .normal:
            return .white
        case .shift:
            return .cyan
        case .commodore:
            return .orange
        }
    }
}

private enum C64VirtualKeyRole {
    case standard
    case shift
    case shiftLock
    case commodore
}

private enum C64KeyLegend {
    case text(String)
    case petscii(UInt8)
    case cursorColor(C64CursorColor)
}

private enum C64CursorColor: String {
    case orange = "ORANGE"
    case brown = "BROWN"
    case lightRed = "LT RED"
    case darkGray = "DK GRAY"
    case mediumGray = "GRAY"
    case lightGreen = "LT GREEN"
    case lightBlue = "LT BLUE"
    case lightGray = "LT GRAY"

    var color: Color {
        switch self {
        case .orange:
            return Color(red: 0.83, green: 0.42, blue: 0.12)
        case .brown:
            return Color(red: 0.43, green: 0.24, blue: 0.12)
        case .lightRed:
            return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .darkGray:
            return Color(white: 0.28)
        case .mediumGray:
            return Color(white: 0.52)
        case .lightGreen:
            return Color(red: 0.55, green: 0.88, blue: 0.45)
        case .lightBlue:
            return Color(red: 0.48, green: 0.68, blue: 0.95)
        case .lightGray:
            return Color(white: 0.76)
        }
    }
}

private struct C64VirtualKey: Identifiable {
    let id: String
    let normalLegend: C64KeyLegend
    let shiftedLegend: C64KeyLegend?
    let commodoreLegend: C64KeyLegend?
    let code: UInt
    let units: CGFloat
    let role: C64VirtualKeyRole

    init(
        _ id: String,
        _ normal: String,
        _ code: UInt,
        shifted: C64KeyLegend? = nil,
        commodore: C64KeyLegend? = nil,
        units: CGFloat = 1,
        role: C64VirtualKeyRole = .standard
    ) {
        self.id = id
        normalLegend = .text(normal)
        shiftedLegend = shifted
        commodoreLegend = commodore
        self.code = code
        self.units = units
        self.role = role
    }

    func legend(for mode: C64KeyboardLegendMode) -> C64KeyLegend {
        switch mode {
        case .normal:
            return normalLegend
        case .shift:
            return shiftedLegend ?? normalLegend
        case .commodore:
            return commodoreLegend ?? shiftedLegend ?? normalLegend
        }
    }
}

private extension C64KeyboardView {
    static let commodoreKeyCode: UInt = 306

    static func shifted(_ text: String) -> C64KeyLegend {
        .text(text)
    }

    static func petscii(_ code: UInt8) -> C64KeyLegend {
        .petscii(code)
    }

    static func color(_ color: C64CursorColor) -> C64KeyLegend {
        .cursorColor(color)
    }

    static let numberRow: [C64VirtualKey] = [
        .init("left-arrow", "←", 96),
        .init("1", "1", 49, shifted: shifted("!"), commodore: color(.orange)),
        .init("2", "2", 50, shifted: shifted("\""), commodore: color(.brown)),
        .init("3", "3", 51, shifted: shifted("#"), commodore: color(.lightRed)),
        .init("4", "4", 52, shifted: shifted("$"), commodore: color(.darkGray)),
        .init("5", "5", 53, shifted: shifted("%"), commodore: color(.mediumGray)),
        .init("6", "6", 54, shifted: shifted("&"), commodore: color(.lightGreen)),
        .init("7", "7", 55, shifted: shifted("'"), commodore: color(.lightBlue)),
        .init("8", "8", 56, shifted: shifted("("), commodore: color(.lightGray)),
        .init("9", "9", 57, shifted: shifted(")"), commodore: shifted(")")),
        .init("0", "0", 48, shifted: shifted("0"), commodore: shifted("0")),
        .init("plus", "+", 45, shifted: petscii(0xDB), commodore: petscii(0xA6)),
        .init("minus", "−", 61, shifted: petscii(0xDD), commodore: petscii(0xAF)),
        .init("pound", "£", 279, shifted: petscii(0xA9), commodore: petscii(0xA8)),
        .init("home", "HOME", 278, shifted: shifted("CLEAR"), commodore: shifted("CLEAR"), units: 1.35),
        .init("delete", "DEL", 8, shifted: shifted("INST"), commodore: shifted("INST"), units: 1.35),
        .init("f1", "F1", 282, shifted: shifted("F2"), commodore: shifted("F2"), units: 1.15)
    ]

    static let qwertyRow: [C64VirtualKey] = [
        .init("ctrl", "CTRL", 9, units: 1.35),
        .init("q", "Q", 113, shifted: petscii(0xD1), commodore: petscii(0xB1)),
        .init("w", "W", 119, shifted: petscii(0xD7), commodore: petscii(0xB3)),
        .init("e", "E", 101, shifted: petscii(0xC5), commodore: petscii(0xB1)),
        .init("r", "R", 114, shifted: petscii(0xD2), commodore: petscii(0xB2)),
        .init("t", "T", 116, shifted: petscii(0xD4), commodore: petscii(0xA3)),
        .init("y", "Y", 121, shifted: petscii(0xD9), commodore: petscii(0xB7)),
        .init("u", "U", 117, shifted: petscii(0xD5), commodore: petscii(0xB8)),
        .init("i", "I", 105, shifted: petscii(0xC9), commodore: petscii(0xA2)),
        .init("o", "O", 111, shifted: petscii(0xCF), commodore: petscii(0xB9)),
        .init("p", "P", 112, shifted: petscii(0xD0), commodore: petscii(0xAF)),
        .init("at", "@", 91, shifted: petscii(0xBA), commodore: petscii(0xA4)),
        .init("asterisk", "*", 93, shifted: petscii(0xC0), commodore: petscii(0xDF)),
        .init("up-arrow", "↑", 92, shifted: shifted("π"), commodore: shifted("π")),
        .init("restore", "RESTORE", 280, units: 1.65),
        .init("f3", "F3", 284, shifted: shifted("F4"), commodore: shifted("F4"), units: 1.15)
    ]

    static let homeRow: [C64VirtualKey] = [
        .init("run-stop", "STOP", 27, shifted: shifted("RUN"), commodore: shifted("RUN"), units: 1.45),
        .init("shift-lock", "SHIFT\nLOCK", 301, units: 1.45, role: .shiftLock),
        .init("a", "A", 97, shifted: petscii(0xC1), commodore: petscii(0xB0)),
        .init("s", "S", 115, shifted: petscii(0xD3), commodore: petscii(0xAE)),
        .init("d", "D", 100, shifted: petscii(0xC4), commodore: petscii(0xAC)),
        .init("f", "F", 102, shifted: petscii(0xC6), commodore: petscii(0xBB)),
        .init("g", "G", 103, shifted: petscii(0xC7), commodore: petscii(0xA5)),
        .init("h", "H", 104, shifted: petscii(0xC8), commodore: petscii(0xB4)),
        .init("j", "J", 106, shifted: petscii(0xCA), commodore: petscii(0xB5)),
        .init("k", "K", 107, shifted: petscii(0xCB), commodore: petscii(0xA1)),
        .init("l", "L", 108, shifted: petscii(0xCC), commodore: petscii(0xB6)),
        .init("colon", ":", 59, shifted: shifted("["), commodore: shifted("[")),
        .init("semicolon", ";", 39, shifted: shifted("]"), commodore: shifted("]")),
        .init("equals", "=", 281, shifted: shifted("="), commodore: shifted("=")),
        .init("return", "RETURN", 13, units: 1.65),
        .init("f5", "F5", 286, shifted: shifted("F6"), commodore: shifted("F6"), units: 1.15)
    ]

    static let bottomRow: [C64VirtualKey] = [
        .init("commodore", "C=", commodoreKeyCode, units: 1.35, role: .commodore),
        .init("left-shift", "SHIFT", 304, units: 1.45, role: .shift),
        .init("z", "Z", 122, shifted: petscii(0xDA), commodore: petscii(0xAD)),
        .init("x", "X", 120, shifted: petscii(0xD8), commodore: petscii(0xBD)),
        .init("c", "C", 99, shifted: petscii(0xC3), commodore: petscii(0xBC)),
        .init("v", "V", 118, shifted: petscii(0xD6), commodore: petscii(0xBE)),
        .init("b", "B", 98, shifted: petscii(0xC2), commodore: petscii(0xBF)),
        .init("n", "N", 110, shifted: petscii(0xCE), commodore: petscii(0xAA)),
        .init("m", "M", 109, shifted: petscii(0xCD), commodore: petscii(0xA7)),
        .init("comma", ",", 44, shifted: shifted("<"), commodore: shifted("<")),
        .init("period", ".", 46, shifted: shifted(">"), commodore: shifted(">")),
        .init("slash", "/", 47, shifted: shifted("?"), commodore: shifted("?")),
        .init("right-shift", "SHIFT", 303, units: 1.45, role: .shift),
        .init("cursor-up", "▲", 273), .init("cursor-down", "▼", 274),
        .init("cursor-left", "◀", 276), .init("cursor-right", "▶", 275),
        .init("f7", "F7", 288, shifted: shifted("F8"), commodore: shifted("F8"), units: 1.15)
    ]

    static let spaceRow: [C64VirtualKey] = [
        .init("insert", "INSERT", 277, units: 1.35),
        .init("space", "SPACE", 32, units: 8.6),
        .init("backspace", "DEL", 8, units: 1.25),
        .init("return-bottom", "RETURN", 13, units: 1.65)
    ]
}

private struct C64VirtualKeyButton: View {
    let key: C64VirtualKey
    let legendMode: C64KeyboardLegendMode
    let isLatched: Bool
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let action: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        legend
            .frame(width: width, height: height)
            .background(keyBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(keyBorder, lineWidth: isLatched ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        action(false)
                    }
            )
            .onDisappear {
                guard pressed else { return }
                pressed = false
                action(false)
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isLatched ? .isSelected : [])
    }

    @ViewBuilder
    private var legend: some View {
        switch key.legend(for: legendMode) {
        case .text(let text):
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.50)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.white)
                .padding(.horizontal, 2)

        case .petscii(let code):
            Text(C64PetsciiGlyph.character(for: code))
                .font(.system(size: fontSize * 1.75, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .foregroundStyle(.white)

        case .cursorColor(let cursorColor):
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(cursorColor.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(.white.opacity(0.42), lineWidth: 0.7)
                    }
                    .frame(width: max(10, min(width * 0.56, 24)), height: max(7, min(height * 0.30, 12)))

                Text(cursorColor.rawValue)
                    .font(.system(size: max(5, fontSize * 0.58), weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 1)
        }
    }

    private var keyBackground: Color {
        if pressed {
            return .white.opacity(0.30)
        }
        if isLatched {
            return legendMode.tint.opacity(0.32)
        }
        return .white.opacity(0.14)
    }

    private var keyBorder: Color {
        isLatched ? legendMode.tint.opacity(0.9) : .white.opacity(0.18)
    }

    private var accessibilityLabel: String {
        switch key.legend(for: legendMode) {
        case .text(let text):
            return text.replacingOccurrences(of: "\n", with: " ")
        case .petscii:
            return "PETSCII graphic"
        case .cursorColor(let color):
            return "\(color.rawValue) cursor color"
        }
    }
}

private enum C64PetsciiGlyph {
    static func character(for code: UInt8) -> String {
        glyphs[code] ?? "◇"
    }

    private static let glyphs: [UInt8: String] = [
        0xA1: "▌", 0xA2: "▄", 0xA3: "▔", 0xA4: "▁",
        0xA5: "▏", 0xA6: "▒", 0xA7: "▕", 0xA8: "▓",
        0xA9: "◤", 0xAA: "▐", 0xAB: "├", 0xAC: "▗",
        0xAD: "└", 0xAE: "┐", 0xAF: "▂", 0xB0: "┌",
        0xB1: "┴", 0xB2: "┬", 0xB3: "┤", 0xB4: "▎",
        0xB5: "▍", 0xB6: "▐", 0xB7: "▀", 0xB8: "▀",
        0xB9: "▃", 0xBA: "◥", 0xBB: "▖", 0xBC: "▝",
        0xBD: "┘", 0xBE: "▘", 0xBF: "▚", 0xC0: "━",
        0xC1: "♠", 0xC2: "│", 0xC3: "━", 0xC4: "▔",
        0xC5: "━", 0xC6: "▁", 0xC7: "▏", 0xC8: "▕",
        0xC9: "╮", 0xCA: "╰", 0xCB: "╯", 0xCC: "◢",
        0xCD: "╲", 0xCE: "╱", 0xCF: "◣", 0xD0: "◤",
        0xD1: "●", 0xD2: "━", 0xD3: "♥", 0xD4: "▎",
        0xD5: "╭", 0xD6: "╳", 0xD7: "○", 0xD8: "♣",
        0xD9: "▕", 0xDA: "♦", 0xDB: "┼", 0xDC: "▓",
        0xDD: "│", 0xDE: "π", 0xDF: "◥"
    ]
}
