import Foundation
import AppKit
import Carbon

struct ShortcutBinding: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        let rawValue: Int

        static let command  = Modifiers(rawValue: 1 << 0)
        static let option   = Modifiers(rawValue: 1 << 1)
        static let control  = Modifiers(rawValue: 1 << 2)
        static let shift    = Modifiers(rawValue: 1 << 3)
        static let function = Modifiers(rawValue: 1 << 4)

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        init(from eventFlags: NSEvent.ModifierFlags) {
            var value: Modifiers = []
            if eventFlags.contains(.command)  { value.insert(.command) }
            if eventFlags.contains(.option)   { value.insert(.option) }
            if eventFlags.contains(.control)  { value.insert(.control) }
            if eventFlags.contains(.shift)    { value.insert(.shift) }
            if eventFlags.contains(.function) { value.insert(.function) }
            self = value
        }

        var cgEventFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if contains(.command)  { flags.insert(.maskCommand) }
            if contains(.option)   { flags.insert(.maskAlternate) }
            if contains(.control)  { flags.insert(.maskControl) }
            if contains(.shift)    { flags.insert(.maskShift) }
            if contains(.function) { flags.insert(.maskSecondaryFn) }
            return flags
        }

        var symbols: [String] {
            var result: [String] = []
            if contains(.function) { result.append("fn") }
            if contains(.control)  { result.append("\u{2303}") }
            if contains(.option)   { result.append("\u{2325}") }
            if contains(.shift)    { result.append("\u{21E7}") }
            if contains(.command)  { result.append("\u{2318}") }
            return result
        }

        static var supportedCGFlagsMask: CGEventFlags {
            [.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift, .maskCommand]
        }
    }

    let modifiers: Modifiers
    let keyCode: Int?

    static let `default`      = ShortcutBinding(modifiers: [.function], keyCode: nil)
    static let defaultHandsFree = ShortcutBinding(modifiers: [.option], keyCode: nil)

    var displayTokens: [String] {
        var tokens = modifiers.symbols
        if let keyCode {
            tokens.append(Self.keyLabel(for: keyCode))
        }
        return tokens
    }

    var displayString: String {
        displayTokens.joined(separator: " ")
    }

    var isValid: Bool {
        !modifiers.isEmpty
    }

    func matchesExactModifiers(_ flags: CGEventFlags) -> Bool {
        let required = modifiers.cgEventFlags
        let relevant = flags.intersection(Modifiers.supportedCGFlagsMask)
        return relevant == required
    }

    static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> ShortcutBinding {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.shortcutBinding),
            let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data),
            binding.isValid
        else {
            return .default
        }
        return binding
    }

    func saveToDefaults(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppPreferenceKey.shortcutBinding)
    }

    static func loadHandsFreeFromDefaults(_ defaults: UserDefaults = .standard) -> ShortcutBinding {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.handsFreeBinding),
            let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data),
            binding.isValid
        else {
            return .defaultHandsFree
        }
        return binding
    }

    func saveHandsFreeToDefaults(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppPreferenceKey.handsFreeBinding)
    }

    private static func keyLabel(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Return:        return "\u{21A9}"
        case kVK_Tab:           return "\u{21E5}"
        case kVK_Space:         return "Space"
        case kVK_Delete:        return "\u{232B}"
        case kVK_ForwardDelete: return "\u{2326}"
        case kVK_Escape:        return "\u{238B}"
        case kVK_LeftArrow:     return "\u{2190}"
        case kVK_RightArrow:    return "\u{2192}"
        case kVK_UpArrow:       return "\u{2191}"
        case kVK_DownArrow:     return "\u{2193}"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return ansiKeyLabel(for: keyCode) ?? "Key \(keyCode)"
        }
    }

    private static func ansiKeyLabel(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Grave:        return "`"
        default: return nil
        }
    }
}
