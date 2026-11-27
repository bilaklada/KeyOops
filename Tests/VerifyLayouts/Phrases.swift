import Foundation
import KeyOopsCore

func checkPhrases(english: KeyboardLayout, russian: KeyboardLayout) throws {
    guard let model = PhraseModel.bundled else { fatalError("Missing phrase model") }
    func append(_ text: String, to passage: inout TypingPassage) {
        precondition(passage.append(text, model: model, english: english, russian: russian))
    }
    func replay(_ text: String, automatic: Bool) -> String {
        var passage = TypingPassage()
        for character in text {
            append(String(character), to: &passage)
            if automatic, passage.original != passage.automaticText {
                passage.commitAutomatic(model: model, english: english, russian: russian)
            }
        }
        return automatic ? passage.original : passage.suggestedText
    }
    let first = "цу all enjoy a little bit of poetry"
    let second = "руку фку ыщьу ща еру иуые сдфыышсфд зщуекн"
    let typed = first + ". " + second + "!\n" + first + "? unfinished"
    let expected = "we all enjoy a little bit of poetry. here are some of the best classical poetry!\nwe all enjoy a little bit of poetry? unfinished"
    for automatic in [false, true] {
        let actual = replay(typed, automatic: automatic)
        precondition(actual == expected, "Automatic=\(automatic): \(actual)")
        for valid in ["цу ", "руку ", "я хочу поднять руку. ", "use x here ", "команда telekom заключила ", "my друг ",
                      "это мой друг ", "name@example.org ", "my name is ", "my file_name "] {
            precondition(replay(valid, automatic: automatic) == valid, "Changed \(valid)")
        }
    }
    for (typed, expected) in [("Ьн name is ", "My name is "), ("Ш фь дфвф ", "I am lada "),
                              ("vjq друг ", "мой друг "), ("Pf,skf gthtrk.xbnm zpsr ", "Забыла переключить язык ")] {
        let actual = replay(typed, automatic: false)
        precondition(actual == expected, "\(typed) -> \(actual)")
    }
    let prefix = model.ending(in: "цу all enjoy ", atDocumentStart: true, english: english, russian: russian)
    precondition(prefix?.replacement == "we" && prefix?.trailingContext == " all enjoy")
    var full = TypingPassage()
    append(String(repeating: "x", count: TypingPassage.capacity), to: &full)
    precondition(!full.append(" ", model: model, english: english, russian: russian))
    precondition(full.original.utf16.count == TypingPassage.capacity)
    var times = [UInt64]()
    var loaded = TypingPassage()
    for _ in 0..<32 {
        for word in (first + " " + second).split(separator: " ") {
            let tick = DispatchTime.now().uptimeNanoseconds
            append(String(word) + " ", to: &loaded)
            times.append(DispatchTime.now().uptimeNanoseconds - tick)
        }
    }
    print("Incremental inference warm p95 \(times.sorted()[times.count * 95 / 100] / 1000) µs")

    for path in CommandLine.arguments.dropFirst() {
        let sentences = try String(contentsOfFile: path, encoding: .utf8)
            .components(separatedBy: "\n").filter { $0.hasPrefix("# text = ") }.dropFirst(900)
        precondition(sentences.count == 100)
        let en = URL(fileURLWithPath: path).lastPathComponent.hasPrefix("en_")
        let (native, other) = en ? (english, russian) : (russian, english)
        var validCount = 0, falseAutomatic = 0, falseHints = 0, recovered = 0, corrupt = 0
        for sentence in sentences {
            let words = sentence.dropFirst(9).lowercased().split(whereSeparator: \.isWhitespace)
            for end in words.indices where end >= 2 {
                let chunk = words[(end-2)...end]
                guard chunk.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { continue }
                let valid = chunk.joined(separator: " ") + " "
                validCount += 1
                if replay(valid, automatic: true) != valid { falseAutomatic += 1; print("False automatic: \(valid) -> \(replay(valid, automatic: true))") }
                if replay(valid, automatic: false) != valid { falseHints += 1 }
                // Alternate between a short layout slip and a longer run.
                let split = end % 3
                let prefix = chunk.prefix(split).map(String.init)
                let suffix = chunk.dropFirst(split).joined(separator: " ")
                guard let wrong = try? native.convert(suffix, to: other),
                      (try? other.convert(wrong, to: native)) == suffix else { continue }
                corrupt += 1
                if replay((prefix + [wrong]).joined(separator: " ") + " ", automatic: true) == valid { recovered += 1 }
            }
        }
        print("\(en ? "EN" : "RU") held-out triples \(validCount), false automatic \(falseAutomatic), false hints \(falseHints), exact automatic recovery \(recovered)/\(corrupt)")
    }
}
