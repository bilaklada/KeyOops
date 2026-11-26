import KeyOopsCore

/// Exercise the production classifier on enabled keyboard tables and count abstentions
/// as misses for wrong-layout input. Each distinct intended word is counted once per set.
func checkCorpus(english: KeyboardLayout, russian: KeyboardLayout) {
    for (label, language, correct, mistakes) in [
        ("English", LayoutLanguage.english, Corpus.englishFrequent, Corpus.englishOnRussian),
        ("Russian", .russian, Corpus.russianFrequent, Corpus.russianOnEnglish)
    ] {
        let (native, other) = language == .english ? (english, russian) : (russian, english)
        func decision(_ typed: String, from: KeyboardLayout, to: KeyboardLayout) -> WordEvidence.Decision {
            guard let reading = try? LayoutLanguage.reading(typed),
                  let candidate = try? from.convert(typed, to: to) else { return .keep }
            return WordEvidence.evaluate(typed, candidate: candidate, source: reading)
        }
        let valid = Set(correct.split(whereSeparator: \.isWhitespace).map(String.init))
        let intended = Set(mistakes.split(whereSeparator: \.isWhitespace).map(String.init))
        var falseEdits = 0, falseHints = 0
        for word in valid {
            switch decision(word, from: native, to: other) {
            case .automatic: falseEdits += 1
            case .suggest: falseHints += 1
            case .keep: break
            }
        }
        var automatic = 0, suggested = 0
        for word in intended {
            guard let typed = try? native.convert(word, to: other),
                  (try? other.convert(typed, to: native)) == word else { continue }
            switch decision(typed, from: other, to: native) {
            case .automatic: automatic += 1
            case .suggest: suggested += 1
            case .keep: break
            }
        }
        print("\(label): \(valid.count) correct words, \(falseEdits) false edits, \(falseHints) false hints.")
        print("\(label): \(intended.count) mistakes, \(automatic) automatic, \(suggested) suggested, \(intended.count - automatic - suggested) missed.")
        precondition(falseEdits == 0, "Correctly typed corpus word would be rewritten")
    }
}
