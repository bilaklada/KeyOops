import Foundation

/// KenLM log10 probabilities and Katz-style ARPA backoff weights. Both
/// languages share one vocabulary, so competing readings use the same scale.
public struct PhraseModel: Sendable {
    private let channel: [[Double]]
    private let unigram: [String: Double]
    private let backoff: [String: Double]
    private let bigram: [String: Double]

    public static let bundled: Self? = {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        guard let url = bundle.url(forResource: "phrases", withExtension: "arpa"),
              let arpa = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let prior = bundle.url(forResource: "layout-channel", withExtension: "json"),
              let data = try? Data(contentsOf: prior),
              let channel = try? JSONDecoder().decode([[Double]].self, from: data),
              channel.count == 2, channel.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else { return nil }
        WordEvidence.prepareDictionaries()
        return Self(arpa, channel: channel)
    }()

    private init?(_ arpa: String, channel: [[Double]]) {
        self.channel = channel
        var uni = [String: Double](), back = [String: Double](), bi = [String: Double]()
        var order = 0
        for line in arpa.split(separator: "\n") {
            if line.first == "\\" {
                order = line == "\\1-grams:" ? 1 : line == "\\2-grams:" ? 2 : 0
                continue
            }
            guard order > 0 else { continue }
            let fields = line.split(separator: "\t")
            guard fields.count >= 2, let score = Double(fields[0]), score.isFinite else { return nil }
            let key = String(fields[1])
            if order == 2 { bi[key] = score }
            else {
                uni[key] = score
                if fields.count == 3 { back[key] = Double(fields[2]) }
            }
        }
        guard uni["<unk>"] != nil, !bi.isEmpty else { return nil }
        unigram = uni
        backoff = back
        bigram = bi
    }

    /// Stateless callers can still ask for one guarded replacement ending before
    /// a space. Live sessions retain the decoder's context between boundaries.
    public func ending(in suffix: String, atDocumentStart: Bool,
                       english: KeyboardLayout, russian: KeyboardLayout) -> LayoutProposal? {
        guard suffix.last == " ", suffix.utf16.count <= LayoutProposal.inspectionLength else { return nil }
        let start = atDocumentStart ? suffix.startIndex : suffix.firstIndex(where: \.isWhitespace)
        guard let start else { return nil }
        var passage = TypingPassage()
        passage.append(String(suffix[start...]), model: self, english: english, russian: russian)
        let typed = passage.original.dropLast().components(separatedBy: " ")
        let suggested = passage.suggestedText.dropLast().components(separatedBy: " ")
        guard typed.count == suggested.count, let language = passage.language,
              let first = typed.indices.first(where: { typed[$0] != suggested[$0] }),
              let last = typed.indices.last(where: { typed[$0] != suggested[$0] }) else { return nil }
        var proposal = LayoutProposal(original: typed[first...last].joined(separator: " "),
            replacement: suggested[first...last].joined(separator: " "), language: language,
            decision: passage.suggestedText == passage.automaticText ? .automatic : .suggest)
        if last + 1 < typed.count { proposal.trailingContext = " " + typed[(last + 1)...].joined(separator: " ") }
        return proposal
    }

    struct Reading {
        let token: String
        let language: LayoutLanguage
        let bias: Double
        let mapped: Bool
    }

    struct Word {
        let typed: String
        let mapped: String
        let source: LayoutLanguage
        let readings: [Reading]
        let isolated: WordEvidence.Decision
        let supported: Bool
    }

    func word(_ typed: String, english: KeyboardLayout, russian: KeyboardLayout) -> Word? {
        guard !typed.isEmpty, typed.utf16.count <= CompletedWord.maximumUTF16Length,
              let source = try? LayoutLanguage.reading(typed) else { return nil }
        let lower = typed.lowercased()
        guard typed == lower || typed == lower.prefix(1).uppercased() + lower.dropFirst() else { return nil }
        let (from, to) = source == .english ? (english, russian) : (russian, english)
        guard let mapped = try? from.convert(typed, to: to) else { return nil }
        let isolated = WordEvidence.evaluate(typed, candidate: mapped, source: source)
        if !typed.allSatisfy(\.isLetter),
           WordEvidence.contextRole(typed, candidate: mapped, source: source) == .boundary && isolated == .keep {
            return nil
        }
        func token(_ word: String) -> String { unigram[word] == nil ? "<unk>" : word }
        let known = WordEvidence.recognizes(typed, in: source)
        let targetKnown = WordEvidence.recognizes(mapped, in: source.opposite)
        let native = Reading(token: token(lower), language: source, bias: known ? 1.1 : 0, mapped: false)
        var alternatives = [native]
        if mapped.allSatisfy(\.isLetter), targetKnown || !known {
            alternatives.append(Reading(token: token(mapped.lowercased()), language: source.opposite,
                                        bias: (targetKnown ? 1.1 : 0) - 0.55, mapped: true))
        }
        return Word(typed: typed, mapped: mapped, source: source, readings: alternatives, isolated: isolated,
                    supported: targetKnown || unigram[mapped.lowercased()] != nil)
    }

    private func transition(_ left: Reading, _ right: Reading, sentenceBreak: Bool) -> Double {
        let unigramScore = unigram[right.token]!
        // Punctuation starts a new lexical phrase, but the writer may still be
        // using the same physical keyboard across the sentence boundary.
        let probability = sentenceBreak ? unigramScore : (bigram[left.token + " " + right.token]
            ?? ((backoff[left.token] ?? 0) + unigramScore))
        // A language change is possible at every boundary, including genuine
        // bilingual prose. The cost is finite in both directions.
        let layoutPrior = channel[left.mapped ? 1 : 0][right.mapped ? 1 : 0]
        let languageSwitchCost = left.language == right.language ? 0.0 : (sentenceBreak ? 1.25 : 1.8)
        return probability + right.bias + 0.3 * layoutPrior - languageSwitchCost
    }

    /// Max-sum forward/backward inference on typed and remapped readings. The
    /// margin at each word compares two complete paths constrained at that word.
    func decode(_ words: [Word], after previousReading: Reading?, previousEndedSentence: Bool,
                sentenceEnds: [Bool]) -> [WordEvidence.Decision] {
        guard let first = words.first else { return [] }
        guard words.count > 1 else { return [first.isolated] }
        var forward = [first.readings.map { reading in
            previousReading.map { transition($0, reading, sentenceBreak: previousEndedSentence) } ?? (unigram[reading.token]! + reading.bias)
        }]
        var edges = [[[Double]]]()
        for i in 1..<words.count {
            let previous = words[i - 1].readings
            let current = words[i].readings
            let edge = previous.map { left in current.map { transition(left, $0, sentenceBreak: sentenceEnds[i - 1]) } }
            edges.append(edge)
            forward.append(current.indices.map { j in
                previous.indices.map { forward[i - 1][$0] + edge[$0][j] }.max()!
            })
        }
        var backward = [Double](repeating: 0, count: words.last!.readings.count)
        var decisions = [WordEvidence.Decision](repeating: .keep, count: words.count)
        for i in words.indices.reversed() {
            if words[i].readings.count == 2 {
                let margin = forward[i][1] + backward[1] - forward[i][0] - backward[0]
                if margin >= 1.45 { decisions[i] = .automatic }
                else if margin >= 0.25 { decisions[i] = .suggest }
                else if margin >= 0 && words[i].isolated != .keep { decisions[i] = .suggest }
            }
            if i > 0 {
                backward = edges[i - 1].map { row in
                    row.indices.map { row[$0] + backward[$0] }.max()!
                }
            }
        }
        // A borrowed name or identifier can be surrounded by another language.
        // An unseen remapping only joins a supported run from the same keyboard.
        for i in words.indices where decisions[i] != .keep && !words[i].supported {
            let neighbors = [i - 1, i + 1].filter { words.indices.contains($0) }
            let joinsRun = neighbors.contains { words[$0].source == words[i].source &&
                words[$0].supported && decisions[$0] != .keep }
            decisions[i] = joinsRun ? .suggest : .keep
        }
        return decisions
    }
}
