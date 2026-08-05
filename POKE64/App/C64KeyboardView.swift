import SwiftUI

struct C64KeyboardView: View {
    @EnvironmentObject private var emulator: EmulatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 7) {
                    keyboardRow(Self.numberRow)
                    keyboardRow(Self.qwertyRow)
                    keyboardRow(Self.homeRow)
                    keyboardRow(Self.bottomRow)
                    keyboardRow(Self.spaceRow)
                }
                .padding(14)
                .frame(minWidth: 1040, alignment: .leading)
            }
            .background(Color.black)
            .navigationTitle("Tastiera Commodore 64")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("La tastiera esterna viene acquisita automaticamente mentre il core è in esecuzione. Nella mappatura VICE: ESC è RUN/STOP, Page Up è RESTORE e Control sinistro è Commodore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func keyboardRow(_ keys: [C64VirtualKey]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                C64VirtualKeyButton(key: key) { pressed in
                    emulator.setRawKey(key.code, pressed: pressed)
                }
            }
        }
    }
}

private struct C64VirtualKey: Identifiable, Sendable {
    let id: String
    let label: String
    let code: UInt
    let units: CGFloat

    init(_ id: String, _ label: String, _ code: UInt, units: CGFloat = 1) {
        self.id = id
        self.label = label
        self.code = code
        self.units = units
    }
}

private extension C64KeyboardView {
    static let numberRow: [C64VirtualKey] = [
        .init("left-arrow", "←", 96),
        .init("1", "1\n!", 49), .init("2", "2\n\"", 50),
        .init("3", "3\n#", 51), .init("4", "4\n$", 52),
        .init("5", "5\n%", 53), .init("6", "6\n&", 54),
        .init("7", "7\n'", 55), .init("8", "8\n(", 56),
        .init("9", "9\n)", 57), .init("0", "0", 48),
        .init("plus", "+", 45), .init("minus", "−", 61),
        .init("pound", "£", 279),
        .init("home", "CLR\nHOME", 278, units: 1.35),
        .init("delete", "INST\nDEL", 8, units: 1.35),
        .init("f1", "F1\nF2", 282, units: 1.15)
    ]

    static let qwertyRow: [C64VirtualKey] = [
        .init("ctrl", "CTRL", 9, units: 1.35),
        .init("q", "Q", 113), .init("w", "W", 119), .init("e", "E", 101),
        .init("r", "R", 114), .init("t", "T", 116), .init("y", "Y", 121),
        .init("u", "U", 117), .init("i", "I", 105), .init("o", "O", 111),
        .init("p", "P", 112), .init("at", "@", 91), .init("asterisk", "*", 93),
        .init("up-arrow", "↑", 92),
        .init("restore", "RESTORE", 280, units: 1.65),
        .init("f3", "F3\nF4", 284, units: 1.15)
    ]

    static let homeRow: [C64VirtualKey] = [
        .init("run-stop", "RUN\nSTOP", 27, units: 1.45),
        .init("shift-lock", "SHIFT\nLOCK", 301, units: 1.45),
        .init("a", "A", 97), .init("s", "S", 115), .init("d", "D", 100),
        .init("f", "F", 102), .init("g", "G", 103), .init("h", "H", 104),
        .init("j", "J", 106), .init("k", "K", 107), .init("l", "L", 108),
        .init("colon", ":\n[", 59), .init("semicolon", ";\n]", 39),
        .init("equals", "=", 281),
        .init("return", "RETURN", 13, units: 1.65),
        .init("f5", "F5\nF6", 286, units: 1.15)
    ]

    static let bottomRow: [C64VirtualKey] = [
        .init("commodore", "C=", 306, units: 1.35),
        .init("left-shift", "SHIFT", 304, units: 1.45),
        .init("z", "Z", 122), .init("x", "X", 120), .init("c", "C", 99),
        .init("v", "V", 118), .init("b", "B", 98), .init("n", "N", 110),
        .init("m", "M", 109), .init("comma", ",\n<", 44),
        .init("period", ".\n>", 46), .init("slash", "/\n?", 47),
        .init("right-shift", "SHIFT", 303, units: 1.45),
        .init("cursor-up", "▲", 273), .init("cursor-down", "▼", 274),
        .init("cursor-left", "◀", 276), .init("cursor-right", "▶", 275),
        .init("f7", "F7\nF8", 288, units: 1.15)
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
    let action: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        Text(key.label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(width: 52 * key.units, height: 52)
            .background(pressed ? .white.opacity(0.30) : .white.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
    }
}
