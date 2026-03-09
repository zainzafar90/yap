import XCTest
@testable import Yap

final class ShortcutBindingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppPreferenceKey.shortcutBinding)
    }

    func testDefaultShortcutIsFn() {
        let binding = ShortcutBinding.default
        XCTAssertTrue(binding.modifiers.contains(.function))
        XCTAssertNil(binding.keyCode)
        XCTAssertTrue(binding.isValid)
    }

    func testEmptyModifiersIsInvalid() {
        XCTAssertFalse(ShortcutBinding(modifiers: [], keyCode: nil).isValid)
    }

    func testSingleModifierIsValid() {
        XCTAssertTrue(ShortcutBinding(modifiers: [.command], keyCode: nil).isValid)
        XCTAssertTrue(ShortcutBinding(modifiers: [.option], keyCode: nil).isValid)
        XCTAssertTrue(ShortcutBinding(modifiers: [.control], keyCode: nil).isValid)
        XCTAssertTrue(ShortcutBinding(modifiers: [.shift], keyCode: nil).isValid)
        XCTAssertTrue(ShortcutBinding(modifiers: [.function], keyCode: nil).isValid)
    }

    func testDisplayTokensModifierOnly() {
        let binding = ShortcutBinding(modifiers: [.command, .shift], keyCode: nil)
        XCTAssertEqual(binding.displayTokens, ["\u{21E7}", "\u{2318}"])
    }

    func testDisplayTokensWithKeyCode() {
        let binding = ShortcutBinding(modifiers: [.command], keyCode: 0)
        XCTAssertEqual(binding.displayTokens.count, 2)
        XCTAssertEqual(binding.displayTokens[0], "\u{2318}")
        XCTAssertEqual(binding.displayTokens[1], "A")
    }

    func testDisplayStringJoinsTokens() {
        let binding = ShortcutBinding(modifiers: [.option, .command], keyCode: nil)
        XCTAssertTrue(binding.displayString.contains("\u{2325}"))
        XCTAssertTrue(binding.displayString.contains("\u{2318}"))
    }

    func testDisplayStringHasNoLeadingOrTrailingSpace() {
        let binding = ShortcutBinding(modifiers: [.command], keyCode: nil)
        XCTAssertFalse(binding.displayString.hasPrefix(" "))
        XCTAssertFalse(binding.displayString.hasSuffix(" "))
    }

    func testCodableRoundTrip() throws {
        let original = ShortcutBinding(modifiers: [.control, .shift], keyCode: 42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripModifierOnly() throws {
        let original = ShortcutBinding(modifiers: [.function], keyCode: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testSaveAndLoadFromDefaults() {
        let defaults = UserDefaults.standard
        let binding = ShortcutBinding(modifiers: [.control, .option], keyCode: 12)
        binding.saveToDefaults(defaults)
        XCTAssertEqual(ShortcutBinding.loadFromDefaults(defaults), binding)
    }

    func testLoadFromDefaultsFallsBackToDefault() {
        XCTAssertEqual(ShortcutBinding.loadFromDefaults(), .default)
    }

    func testSavingInvalidBindingFallsBackToDefault() {
        let defaults = UserDefaults.standard
        let invalid = ShortcutBinding(modifiers: [], keyCode: nil)
        invalid.saveToDefaults(defaults)
        XCTAssertEqual(ShortcutBinding.loadFromDefaults(defaults), .default)
    }

    func testModifierSymbolOrder() {
        let modifiers: ShortcutBinding.Modifiers = [.function, .control, .option, .shift, .command]
        XCTAssertEqual(modifiers.symbols, ["fn", "\u{2303}", "\u{2325}", "\u{21E7}", "\u{2318}"])
    }

    func testModifierSymbolsSingleCommand() {
        XCTAssertEqual(ShortcutBinding.Modifiers.command.symbols, ["\u{2318}"])
    }

    func testModifierSymbolsSingleOption() {
        XCTAssertEqual(ShortcutBinding.Modifiers.option.symbols, ["\u{2325}"])
    }

    func testCGEventFlagsMapping() {
        let modifiers: ShortcutBinding.Modifiers = [.command, .option]
        let flags = modifiers.cgEventFlags
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertFalse(flags.contains(.maskControl))
        XCTAssertFalse(flags.contains(.maskShift))
    }

    func testCGEventFlagsAllModifiers() {
        let modifiers: ShortcutBinding.Modifiers = [.command, .option, .control, .shift, .function]
        let flags = modifiers.cgEventFlags
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertTrue(flags.contains(.maskControl))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertTrue(flags.contains(.maskSecondaryFn))
    }

    func testEquality() {
        let a = ShortcutBinding(modifiers: [.command], keyCode: 0)
        let b = ShortcutBinding(modifiers: [.command], keyCode: 0)
        let c = ShortcutBinding(modifiers: [.command], keyCode: 1)
        let d = ShortcutBinding(modifiers: [.option], keyCode: 0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testMatchesExactModifiers() {
        let binding = ShortcutBinding(modifiers: [.command, .option], keyCode: nil)
        var flags: CGEventFlags = [.maskCommand, .maskAlternate]
        XCTAssertTrue(binding.matchesExactModifiers(flags))
        flags.insert(.maskShift)
        XCTAssertFalse(binding.matchesExactModifiers(flags))
    }

    func testMatchesExactModifiersIgnoresNonRelevantFlags() {
        let binding = ShortcutBinding(modifiers: [.command], keyCode: nil)
        let flags: CGEventFlags = [.maskCommand, .maskNonCoalesced]
        XCTAssertTrue(binding.matchesExactModifiers(flags))
    }
}
