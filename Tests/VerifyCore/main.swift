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
try check("Known phrase", Assessment.suggests(original: "руддщ цщкдв", candidate: "hello world", source: .russian))
try check("Known original retained", !Assessment.suggests(original: "hello", candidate: "мир", source: .english))
try check("Unknown target", !Assessment.suggests(original: "руддщ ффф", candidate: "hello aaa", source: .russian))
try check("Valid Russian", !Assessment.suggests(original: "мир", candidate: "vbh", source: .russian))
try check("Frequent wrong layout", WordEvidence.evaluate("ghbdtn", candidate: "привет", source: .english) == .automatic)
try check("Reverse evidence", WordEvidence.evaluate("руддщ", candidate: "hello", source: .russian) == .automatic)
try check("Real source word", WordEvidence.evaluate("tot", candidate: "еще", source: .english) == .keep)
try check("Code token", WordEvidence.evaluate("var123", candidate: "мир123", source: .english) == .keep)
try check("Completed word", CompletedWord.read(suffix: "test ghbdtn ", startsAtDocumentBeginning: false) == "ghbdtn")
try check("First word", CompletedWord.read(suffix: "руддщ ", startsAtDocumentBeginning: true) == "руддщ")
try check("Partial token", CompletedWord.read(suffix: "руддщ ", startsAtDocumentBeginning: false) == nil)
try check("Pending space", CompletedWord.read(suffix: "ghbdtn", startsAtDocumentBeginning: true) == nil)
try check("Double space", CompletedWord.read(suffix: "hello  ", startsAtDocumentBeginning: true) == nil)
try check("Initials stay manual", WordEvidence.evaluate("GHBDTN", candidate: "ПРИВЕТ", source: .english) == .suggest)
try check("Short suggestion", WordEvidence.evaluate("vbh", candidate: "мир", source: .english) == .suggest)
try check("Russian letter on comma key", WordEvidence.evaluate(",skj", candidate: "было", source: .english) == .suggest)
try check("Punctuated English is protected", WordEvidence.evaluate("he.", candidate: "рую", source: .english) == .keep)


// Printable rows on ABC and Russian. The shifted period and comma occupy
// the same physical keys as capital Ю and Б in the second layout.
func punctuationFixture(_ base: String, _ shifted: String) -> KeyboardLayout {
    var outputs: [PhysicalKey: Character] = [:]
    for (code, pair) in zip(base, shifted).enumerated() {
        outputs[PhysicalKey(code: UInt16(code), shifted: false)] = pair.0
        outputs[PhysicalKey(code: UInt16(code), shifted: true)] = pair.1
    }
    return KeyboardLayout(outputs: outputs)
}

let enRow = "qwertyuiop[]asdfghjkl;'zxcvbnm,."
let ruRow = "йцукенгшщзхъфывапролджэячсмитьбю"
let abc = punctuationFixture(enRow, "QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>")
let ru = punctuationFixture(ruRow, ruRow.uppercased())

@MainActor func phrase(_ text: String, start: Bool = true) -> LayoutProposal? {
    LayoutProposal.ending(in: text, atDocumentStart: start, english: abc, russian: ru)
}

let sentence = phrase("Pf,skf gthtrk.xbnm zpsr ")
try check("Reported sentence", sentence?.replacement == "Забыла переключить язык" && sentence?.decision == .automatic)
try check("No premature edit", phrase("Pf,skf gthtrk.xbnm zpsr") == nil)
try check("One ambiguous letter", phrase("z ") == nil && phrase("Ш ") == nil)
try check("Weak context is a suggestion", phrase("z ghbdtn ")?.decision == .suggest)
try check("Short function word recovered", phrase("z ghbdtn zpsr ")?.replacement == "я привет язык")
let preposition = try ru.convert("в новый город", to: abc)
try check("Preposition recovered", phrase(preposition + " ")?.replacement == "в новый город")
let reverse = try abc.convert("I forgot the language", to: ru)
let englishPhrase = phrase(reverse + " ")
try check("Reverse pronoun and article", englishPhrase?.replacement == "I forgot the language" && englishPhrase?.decision == .suggest)
try check("Do not take a variable from English", phrase("axis z ghbdtn zpsr ")?.original == "ghbdtn zpsr")
try check("Repeated evidence", phrase("z ghbdtn ghbdtn ")?.decision == .suggest)
try check("Valid source boundary", phrase("hello ghbdtn zpsr ")?.original == "ghbdtn zpsr")
try check("Newline boundary", phrase("z ghbdtn\nzpsr ")?.original == "zpsr")
try check("Double-space boundary", phrase("z ghbdtn  zpsr ")?.original == "zpsr")
try check("Clipped left edge", phrase("ghbdtn zpsr ", start: false)?.original == "zpsr")
for text in ["I forgot the language ", "Я забыла переключить язык ", "set variable z ", "hello мир ",
             "mail user@example.com ", "visit https://example.com ", "let user_id ", "read API "] {
    try check("Preserve legitimate input", phrase(text) == nil)
}
// Simulate Spaces as they arrive. Once an automatic correction switches the
// layout, later words render normally under the intended layout.
@MainActor func simulate(_ intended: String, in language: LayoutLanguage) throws -> String {
    let (native, wrong) = language == .english ? (abc, ru) : (ru, abc)
    var text = ""
    var switched = false
    for word in intended.split(separator: " ") {
        text += (switched ? String(word) : try native.convert(String(word), to: wrong)) + " "
        if let edit = phrase(text), edit.decision == .automatic {
            text.removeLast(edit.original.count + 1)
            text += edit.replacement + " "
            switched = true
        }
    }
    return text
}
try check("Incremental Russian", try simulate("Забыла переключить язык", in: .russian) == "Забыла переключить язык ")
try check("Incremental English", try simulate("I forgot language", in: .english) == "I forgot language ")
for sentence in ["I forgot to switch my keyboard", "Я забыла переключить язык", "Отправь мне ссылку на документ",
                 "We meet at the office today", "Open файл в TextEdit", "assign z to variable x",
                 "send it to me tomorrow", "я и ты идём в парк", "Version два готова", "my email is support@example.com"] {
    var prefix = ""
    for token in sentence.split(separator: " ") {
        prefix += token + " "
        try check("Preserve each valid prefix", phrase(prefix) == nil)
    }
}
print("Core and phrase checks passed.")

// Exercise the live decoder with the same layout switch the host performs after
// an automatic edit. Subsequent keys then arrive in their intended script.
for intended in ["we all enjoy a little bit of poetry", "here are some of the best classical poetry",
                 "мы с тобой уже знакомы"] {
    let native = try LayoutLanguage.reading(intended)
    let (from, to) = native == .english ? (abc, ru) : (ru, abc)
    let model = PhraseModel.bundled!
    var session = TypingPassage()
    var switched = false
    for word in intended.split(separator: " ") {
        let typed = switched ? String(word) : try from.convert(String(word), to: to)
        try check("Append live word", session.append(typed + " ", model: model, english: abc, russian: ru))
        if session.original != session.automaticText {
            session.commitAutomatic(model: model, english: abc, russian: ru)
            switched = true
        }
    }
    try check("Live keyboard switch: \(session.original)", session.original == intended + " ")
}
