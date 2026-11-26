import KeyOopsCore

struct CheckFailure: Error { let description: String }

func check(_ name: String, _ matches: @autoclosure () throws -> Bool) throws {
    guard try matches() else { throw CheckFailure(description: name) }
}

func rejects<T>(_ expected: ConversionError, _ operation: () throws -> T) throws {
    do {
        _ = try operation()
        throw CheckFailure(description: "Expected rejection: \(expected)")
    } catch let error as ConversionError {
        try check("Rejection reason", error == expected)
    }
}

func fixture(_ row: String) -> KeyboardLayout {
    var outputs: [PhysicalKey: Character] = [:]
    for (index, letter) in row.enumerated() {
        outputs[PhysicalKey(code: UInt16(index), shifted: false)] = letter
        outputs[PhysicalKey(code: UInt16(index), shifted: true)] = Character(letter.uppercased())
    }
    return KeyboardLayout(outputs: outputs)
}

let english = fixture("qwertyuiopasdfghjklzxcvbnm")
let russian = fixture("йцукенгшщзфывапролдячсмить")
try check("English to Russian", english.convert("Ghbdtn\nvbh", to: russian) == "Привет\nмир")
try check("Russian to English", russian.convert("Руддщ цщкдв", to: english) == "Hello world")
try check("Russian script", LayoutLanguage.reading("Ёж!") == .russian)
try check("English script", LayoutLanguage.reading("GHBDTN") == .english)
try rejects(.mixed) { try LayoutLanguage.reading("Hello мир") }
try rejects(.noLetters) { try LayoutLanguage.reading("123!") }
try rejects(.unsupported) { try LayoutLanguage.reading("Čaj") }

let base = PhysicalKey(code: 0, shifted: false)
let shift = PhysicalKey(code: 0, shifted: true)
let digits = KeyboardLayout(outputs: [base: "2", shift: "@"])
let symbols = KeyboardLayout(outputs: [base: "2", shift: "\""])
try check("Shifted punctuation", digits.convert("2@", to: symbols) == "2\"")
try rejects(.ambiguous) { try KeyboardLayout(outputs: [base: ".", shift: "."]).convert(".", to: digits) }
try rejects(.unsupported) { try digits.convert("2🐈", to: symbols) }
print("Core checks passed.")
try check("Known phrase", Assessment.suggests(original: "руддщ цщкдв", candidate: "hello world", source: .russian))
try check("Known original retained", !Assessment.suggests(original: "hello", candidate: "мир", source: .english))
try check("Unknown target", !Assessment.suggests(original: "руддщ ффф", candidate: "hello aaa", source: .russian))
try check("Valid Russian", !Assessment.suggests(original: "мир", candidate: "vbh", source: .russian))
try check("Frequent wrong layout", WordEvidence.evaluate("ghbdtn", candidate: "привет", source: .english) == .automatic)
try check("Reverse evidence", WordEvidence.evaluate("руддщ", candidate: "hello", source: .russian) == .automatic)
try check("Real source word", WordEvidence.evaluate("tot", candidate: "еще", source: .english) == .keep)
try check("Code token", WordEvidence.evaluate("var123", candidate: "мир123", source: .english) == .keep)
