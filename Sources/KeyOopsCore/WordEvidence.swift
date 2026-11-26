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
