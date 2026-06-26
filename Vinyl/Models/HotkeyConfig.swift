import AppKit
import Combine

// MARK: - Action

enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case playPause = "playPause"
    case previous  = "previous"
    case next      = "next"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .previous:  return "Previous Track"
        case .next:      return "Next Track"
        }
    }
}

// MARK: - Binding

struct HotkeyBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifierRaw: UInt

    var modifiers: NSEvent.ModifierFlags { .init(rawValue: modifierRaw) }

    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyLabel(keyCode)
        return s
    }

    static func keyLabel(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X",
            8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R",
            16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5",
            25:"9", 26:"7", 28:"8", 29:"0",
            31:"O", 32:"U", 34:"I", 35:"P",
            37:"L", 38:"J", 40:"K", 45:"N", 46:"M",
            36:"↩", 48:"⇥", 49:"Space", 51:"⌫", 53:"Esc",
            123:"←", 124:"→", 125:"↓", 126:"↑"
        ]
        return map[code] ?? "?"
    }

    // MARK: Defaults
    static let ctrl_cmd: UInt = NSEvent.ModifierFlags([.control, .command]).rawValue

    static let defaults: [HotkeyAction: HotkeyBinding] = [
        .playPause: HotkeyBinding(keyCode: 35,  modifierRaw: ctrl_cmd),   // ⌃⌘P
        .previous:  HotkeyBinding(keyCode: 123, modifierRaw: ctrl_cmd),   // ⌃⌘←
        .next:      HotkeyBinding(keyCode: 124, modifierRaw: ctrl_cmd)    // ⌃⌘→
    ]
}

// MARK: - Config store

final class HotkeyConfig: ObservableObject {
    static let shared = HotkeyConfig()

    @Published private(set) var bindings: [HotkeyAction: HotkeyBinding] = [:]

    private init() { load() }

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        bindings[action] ?? HotkeyBinding.defaults[action]!
    }

    func set(_ binding: HotkeyBinding, for action: HotkeyAction) {
        bindings[action] = binding
        save()
    }

    func resetToDefaults() {
        bindings = HotkeyBinding.defaults
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "hotkeyBindings"),
              let dict = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) else {
            bindings = HotkeyBinding.defaults
            return
        }
        bindings = Dictionary(uniqueKeysWithValues:
            dict.compactMap { k, v in HotkeyAction(rawValue: k).map { ($0, v) } }
        )
        // Fill any missing keys with defaults
        for action in HotkeyAction.allCases {
            if bindings[action] == nil { bindings[action] = HotkeyBinding.defaults[action] }
        }
    }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "hotkeyBindings")
        }
    }
}
