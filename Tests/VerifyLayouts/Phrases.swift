import Foundation
import KeyOopsCore

func checkPhrases(english: KeyboardLayout, russian: KeyboardLayout) throws {
    let start = DispatchTime.now().uptimeNanoseconds
    guard let model = PhraseModel.bundled else { fatalError("Missing KenLM resource") }
    print("Cold model load: \((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) ms")
    func hint(_ text: String) -> LayoutProposal? {
        model.ending(in: text + " ", atDocumentStart: true, english: english, russian: russian)
    }
    for (typed, expected) in [("Ьн name is", "My"), ("Ш фь дфвф", "I am lada"),
                              ("vjq друг", "мой")] {
        let result = hint(typed)
        print("Fixture \(typed) -> \(result?.replacement ?? "(none)")")
        precondition(result?.replacement == expected && result?.decision == .suggest)
    }
    for valid in ["my name is", "это мой друг", "use x here", "my друг", "name@example.org",
                  "x", "Ерфые", "Ьн  name is", "Ьн\nname is"] {
        precondition(hint(valid) == nil, "Unexpected suggestion for \(valid)")
    }
    // Optional held-out PUD benchmark. Training uses sentences 1...900.
    for path in CommandLine.arguments.dropFirst() {
        let sentences = try String(contentsOfFile: path, encoding: .utf8)
            .components(separatedBy: "\n").filter { $0.hasPrefix("# text = ") }.dropFirst(900)
        precondition(sentences.count == 100)
        let isEnglish = URL(fileURLWithPath: path).lastPathComponent.hasPrefix("en_")
        let (native, other) = isEnglish ? (english, russian) : (russian, english)
        var count = 0, exact = 0, falseHints = 0, any = 0
        var hybridExact = 0, hybridFalse = 0, recovered = 0
        var times = [UInt64]()
        for sentence in sentences {
            let words = sentence.dropFirst(9).lowercased().split(whereSeparator: \.isWhitespace)
            for end in words.indices where end >= 2 {
                let chunk = words[(end-2)...end]
                guard chunk.allSatisfy({ $0.allSatisfy(\.isLetter) }) else { continue }
                let valid = chunk.joined(separator: " ")
                guard let wrong = try? native.convert(valid, to: other),
                      (try? other.convert(wrong, to: native)) == valid else { continue }
                count += 1
                func deterministic(_ text: String) -> LayoutProposal? {
                    LayoutProposal.ending(in: text + " ", atDocumentStart: true, english: english, russian: russian)
                }
                let falseHint = hint(valid)
                if falseHint != nil { falseHints += 1 }
                if deterministic(valid) ?? falseHint != nil { hybridFalse += 1 }
                let existing = deterministic(wrong)
                let tick = DispatchTime.now().uptimeNanoseconds
                let suggestion = hint(wrong)
                times.append(DispatchTime.now().uptimeNanoseconds - tick)
                if let combined = existing ?? suggestion, combined.original == wrong && combined.replacement == valid {
                    hybridExact += 1
                    if existing == nil { recovered += 1 }
                }
                if let suggestion {
                    any += 1
                    if suggestion.original == wrong && suggestion.replacement == valid { exact += 1 }
                }
            }
        }
        times.sort()
        precondition(!times.isEmpty)
        print("Hybrid exact: \(hybridExact); newly recovered: \(recovered); false hints: \(hybridFalse)")
        print("\(isEnglish ? "English" : "Russian") held-out triples: \(count); exact \(exact); any hint \(any); false hints \(falseHints); warm p95 \(times[times.count * 95 / 100] / 1000) µs")
    }
}
