import Foundation

public enum WordEvidence {
    public enum Decision { case keep, suggest, automatic }

    private static let dictionaries: [LayoutLanguage: Lexicon] = {
        var result: [LayoutLanguage: Lexicon] = [:]
        for (language, code) in [(LayoutLanguage.english, "en"), (.russian, "ru")] {
            let shipped = Bundle.main.url(forResource: code + "-lex", withExtension: "bin")
            let url = Bundle.main.bundleURL.pathExtension == "app" ? shipped
                : Bundle.module.url(forResource: code + "-lex", withExtension: "bin")
            if let url, let data = try? Data(contentsOf: url),
               let lexicon = try? Lexicon.decode(data), lexicon.lang == language { result[language] = lexicon }
        }
        return result
    }()

    enum ContextRole { case boundary, anchor, dependent }

    private static let shortEnglish: Set<String> = ["a", "i", "in", "of", "to", "on", "at", "by", "we", "he", "it", "me", "my", "as", "is", "am", "be", "or", "if", "so", "us"]
    private static let shortRussian: Set<String> = ["я", "и", "в", "к", "с", "у", "о", "а", "на", "не", "мы", "вы", "он", "ты", "из", "по", "за", "до", "от", "но"]

    static func contextRole(_ word: String, candidate: String, source: LayoutLanguage) -> ContextRole {
        guard candidate.allSatisfy(\.isLetter), word.count == candidate.count,
              let original = dictionaries[source], let target = dictionaries[source.opposite] else { return .boundary }
        let lower = word.lowercased()
        let normalCase = word == lower || word == lower.prefix(1).uppercased() + lower.dropFirst()
        guard normalCase else { return .boundary }
        let sourceFunctions = source == .english ? shortEnglish : shortRussian
        let targetFunctions = source == .english ? shortRussian : shortEnglish
        if word.count <= 2 {
            // A single arbitrary key may be a variable. It can join a contextual
            // proposal, but cannot supply evidence for one.
            guard word.allSatisfy(\.isLetter), targetFunctions.contains(candidate.lowercased()),
                  !sourceFunctions.contains(lower), word.count == 1 || !original.contains(word)
            else { return .boundary }
            return .dependent
        }
        guard !original.contains(word), target.contains(candidate) else { return .boundary }
        if word.count == 3 {
            // Pronouns, prepositions and nouns of this length can link stronger words.
            return word.allSatisfy(\.isLetter) ? .dependent : .boundary
        }
        if !word.allSatisfy(\.isLetter) {
            // Internal punctuation can be a physical letter key. Never cross a
            // terminal punctuation mark, identifier delimiter, URL or email separator.
            let letterKeys = ",.[];'"
            guard source == .english, word.first?.isLetter == true, word.last?.isLetter == true,
                  word.allSatisfy({ $0.isLetter || letterKeys.contains($0) }) else { return .boundary }
            let fragments = word.split(whereSeparator: { !$0.isLetter })
            let known = fragments.filter { original.contains(String($0)) }
            if !known.isEmpty {
                // A short dictionary abbreviation inside a comma-key spelling (Pf in
                // Pf,skf) may join a phrase but must never vote for automatic correction.
                guard fragments.count == 2, word.filter({ !$0.isLetter }) == ",",
                      known.count == 1, let fragment = known.first, fragment.count <= 2,
                      !sourceFunctions.contains(fragment.lowercased()) else { return .boundary }
                return .dependent
            }
        }
        return .anchor
    }

    public static func evaluate(_ text: String, candidate: String, source: LayoutLanguage) -> Decision {
        guard text.count >= 3, text.count <= CompletedWord.maximumUTF16Length,
              candidate.allSatisfy(\.isLetter), candidate.count == text.count,
              let original = dictionaries[source], let target = dictionaries[source.opposite],
              !original.contains(text), target.contains(candidate) else { return .keep }
        if !text.allSatisfy(\.isLetter) {
            // ABC punctuation keys can represent letters on Russian (for example ,skj → было).
            // Keep actual words with punctuation, identifiers and URLs out of suggestions.
            let letterKeys = ",.[];'`<>{}:\"~"
            guard source == .english, text.allSatisfy({ $0.isLetter || letterKeys.contains($0) }),
                  !text.split(whereSeparator: { !$0.isLetter }).contains(where: { original.contains(String($0)) })
            else { return .keep }
            return .suggest
        }
        let ordinaryCase = text == text.lowercased() || String(text.prefix(1)).uppercased() + text.dropFirst().lowercased() == text
        let frequent = target.isCore(candidate) || Assessment.suggests(original: text, candidate: candidate, source: source)
        return frequent && ordinaryCase && text.count >= 4 ? .automatic : .suggest
    }
}
