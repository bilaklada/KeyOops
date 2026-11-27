import Foundation

/// KenLM log10 probabilities and Katz-style ARPA backoff weights. Both
/// languages share one vocabulary, so competing readings use the same scale.
public struct PhraseModel: Sendable {
    private let unigram: [String: Double]
    private let backoff: [String: Double]
    private let bigram: [String: Double]

    public static let bundled: Self? = {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        guard let url = bundle.url(forResource: "phrases", withExtension: "arpa"),
              let arpa = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Self(arpa)
    }()

    private init?(_ arpa: String) {
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

    private func score(_ words: [String]) -> Double {
        var total = 0.0
        var previous: String?
        for word in words {
            let token = unigram[word] == nil ? "<unk>" : word
            let single = unigram[token]!
            if let previous {
                total += bigram[previous + " " + token] ?? ((backoff[previous] ?? 0) + single)
            } else { total += single }
            previous = token
        }
        return total
    }

    public func ending(in suffix: String, atDocumentStart: Bool,
                       english: KeyboardLayout, russian: KeyboardLayout) -> LayoutProposal? {
        guard suffix.last == " ", suffix.utf16.count <= LayoutProposal.inspectionLength else { return nil }
        let all = suffix.dropLast().components(separatedBy: " ")
        var tokens = Array(all.suffix(8))
        if !atDocumentStart && tokens.count == all.count {
            tokens.removeFirst()
        }
        // A punctuation mark, line break, identifier or double space ends the span.
        if let boundary = tokens.lastIndex(where: { $0.isEmpty || !$0.allSatisfy(\.isLetter) }) {
            tokens.removeFirst(boundary + 1)
        }
        guard tokens.count >= 2 else { return nil }
        let lower = tokens.map { $0.lowercased() }
        let baseline = score(lower)
        var strongestGain = 1.5
        var result: LayoutProposal?
        for start in tokens.indices {
            guard let source = try? LayoutLanguage.reading(tokens[start]) else { continue }
            let (from, to) = source == .english ? (english, russian) : (russian, english)
            var candidate = tokens
            var unknownSource = false
            for end in start..<tokens.count {
                let word = tokens[end]
                guard (try? LayoutLanguage.reading(word)) == source,
                      word == lower[end] || word == lower[end].capitalized,
                      let mapped = try? from.convert(word, to: to), mapped.allSatisfy(\.isLetter) else { break }
                candidate[end] = mapped
                unknownSource = unknownSource || !WordEvidence.recognizes(word, in: source)
                guard unknownSource else { continue }
                // A candidate must connect with an observed phrase. Unknown proper
                // names may accompany it, but cannot supply that evidence alone.
                let readings = candidate.map { $0.lowercased() }
                let hasPair = (max(0, start - 1)..<min(end + 1, tokens.count - 1)).contains {
                    bigram[readings[$0] + " " + readings[$0 + 1]] != nil
                }
                guard hasPair else { continue }
                let gain = score(readings) - baseline
                guard gain > strongestGain || (result != nil && gain == strongestGain && end > start &&
                    end == tokens.count - 1 && !WordEvidence.recognizes(word, in: source)) else { continue }
                strongestGain = gain
                result = LayoutProposal(original: tokens[start...end].joined(separator: " "),
                                        replacement: candidate[start...end].joined(separator: " "),
                                        language: source, decision: .suggest)
                if end + 1 < tokens.count {
                    result?.trailingContext = " " + tokens[(end + 1)...].joined(separator: " ")
                }
            }
        }
        return result
    }
}
