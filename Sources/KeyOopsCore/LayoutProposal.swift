public struct LayoutProposal {
    // Four ordinary words fit here without reading a paragraph from the editor.
    public static let inspectionLength = 160
    private static let maximumWords = 4
    public let original: String
    public let replacement: String
    public let language: LayoutLanguage
    public internal(set) var trailingContext = ""
    public let decision: WordEvidence.Decision

    public static func ending(in suffix: String, atDocumentStart: Bool,
                              english: KeyboardLayout, russian: KeyboardLayout) -> Self? {
        guard suffix.last == " ", suffix.utf16.count <= inspectionLength else { return nil }
        var remainder = suffix.dropLast()
        var words: [String] = []
        var candidates: [String] = []
        var anchors = Set<String>()
        var leadingShortAfterText = false
        var ambiguous = false
        var source: LayoutLanguage?
        var fallback: Self?

        while words.count < maximumWords && !remainder.isEmpty {
            let start = remainder.lastIndex(where: { $0.isWhitespace }).map { remainder.index(after: $0) }
                ?? remainder.startIndex
            let word = String(remainder[start...])
            guard start != remainder.startIndex || atDocumentStart,
                  !word.isEmpty, word.utf16.count <= CompletedWord.maximumUTF16Length,
                  let language = try? LayoutLanguage.reading(word),
                  source == nil || language == source else { break }
            source = language
            let (from, to) = language == .english ? (english, russian) : (russian, english)
            guard let candidate = try? from.convert(word, to: to) else { break }
            if words.isEmpty {
                let decision = WordEvidence.evaluate(word, candidate: candidate, source: language)
                if decision != .keep {
                    fallback = Self(original: word, replacement: candidate, language: language, decision: decision)
                }
            }
            let role = WordEvidence.contextRole(word, candidate: candidate, source: language)
            guard role != .boundary else { break }
            if role == .ambiguous { ambiguous = true }
            if role == .anchor { anchors.insert(candidate.lowercased()) }
            leadingShortAfterText = word.count <= 2 && start != remainder.startIndex
                && remainder[..<start].dropLast().last?.isWhitespace == false
            words.append(word)
            candidates.append(candidate)
            guard start != remainder.startIndex else { break }
            let separator = remainder.index(before: start)
            guard remainder[separator] == " " else { break }
            remainder = remainder[..<separator]
        }
        // A trailing variable in an otherwise unrelated span ("axis z") can look
        // exactly like the pronoun я. Preserve it when the preceding text was excluded.
        if leadingShortAfterText {
            words.removeLast()
            candidates.removeLast()
        }
        guard words.count >= 2, let source, !anchors.isEmpty, !ambiguous || anchors.count >= 2 else { return fallback }
        return Self(original: words.reversed().joined(separator: " "),
                    replacement: candidates.reversed().joined(separator: " "),
                    language: source, decision: anchors.count >= 2 && !ambiguous ? .automatic : .suggest)
    }
}
