import Foundation

/// Append-only state for one focused editor. Completed chunks retain their text,
/// while only the current sentence fragment participates in further inference.
public struct TypingPassage {
    public static let capacity = 4096
    static let window = 16
    public private(set) var original = ""
    private var confirmed = ""
    private var proposed = ""
    private var active: [PhraseModel.Word] = []
    private var separators: [String] = []
    private var decisions: [WordEvidence.Decision] = []
    private var previous: PhraseModel.Reading?
    private var previousEndedSentence = false
    private var unfinished = ""
    private var automatic = ""
    private var suggestion = ""
    private var frozenLanguage: LayoutLanguage?
    private var frozenAutomaticLanguage: LayoutLanguage?
    public private(set) var language: LayoutLanguage?
    public private(set) var automaticLanguage: LayoutLanguage?

    public init() {}
    public var suggestedText: String { proposed + suggestion + unfinished }
    public var automaticText: String { confirmed + automatic + unfinished }

    /// The caller keeps the existing proposal available when the capacity is reached.
    @discardableResult public mutating func append(_ text: String, model: PhraseModel,
                                                    english: KeyboardLayout, russian: KeyboardLayout) -> Bool {
        guard original.utf16.count + text.utf16.count <= Self.capacity else { return false }
        original += text
        for character in text {
            guard character.isWhitespace else { unfinished.append(character); continue }
            if !unfinished.isEmpty {
                let end = unfinished.lastIndex(where: { !".!?,…:;".contains($0) })
                    .map { unfinished.index(after: $0) } ?? unfinished.startIndex
                let word = String(unfinished[..<end])
                let punctuation = String(unfinished[end...])
                unfinished = ""
                if let reading = model.word(word, english: english, russian: russian) {
                    if active.count == Self.window { freezePrefix() }
                    active.append(reading)
                    separators.append(punctuation + String(character))
                    render(model)
                } else {
                    finish()
                    confirmed += word + punctuation + String(character)
                    proposed += word + punctuation + String(character)
                }
            } else {
                finish()
                confirmed.append(character)
                proposed.append(character)
            }
        }
        return true
    }

    private mutating func finish() {
        previous = nil
        frozenLanguage = language
        frozenAutomaticLanguage = automaticLanguage
        confirmed += automatic
        proposed += suggestion
        active.removeAll(keepingCapacity: true)
        separators.removeAll(keepingCapacity: true)
        automatic = ""
        suggestion = ""
    }

    /// Freeze the oldest half of a full window. Keep the adjacent reading
    /// as left context and leave the recent half open to later evidence.
    private mutating func freezePrefix() {
        let count = Self.window / 2
        for i in 0..<count {
            let word = active[i], decision = decisions[i]
            proposed += (decision == .keep ? word.typed : word.mapped) + separators[i]
            confirmed += (decision == .automatic ? word.mapped : word.typed) + separators[i]
            if decision != .keep { frozenLanguage = word.source }
            if decision == .automatic { frozenAutomaticLanguage = word.source }
            previous = word.readings[decision == .keep ? 0 : 1]
            previousEndedSentence = Self.endsSentence(separators[i])
        }
        active.removeFirst(count)
        separators.removeFirst(count)
    }

    public mutating func commitAutomatic(model: PhraseModel, english: KeyboardLayout, russian: KeyboardLayout) {
        original = automaticText
        for i in active.indices where decisions[i] == .automatic {
            let word = active[i]
            // A committed spelling supplies left/right context, but should not
            // immediately be proposed in reverse.
            if let mapped = model.word(word.mapped, english: english, russian: russian) {
                active[i] = PhraseModel.Word(typed: mapped.typed, mapped: mapped.mapped, source: mapped.source,
                                             readings: [mapped.readings[0]], isolated: .keep, supported: true)
            }
        }
        render(model)
    }

    private static func endsSentence(_ separator: String) -> Bool {
        separator.contains { $0.isNewline || ".!?…".contains($0) }
    }

    private mutating func render(_ model: PhraseModel) {
        language = frozenLanguage
        automaticLanguage = frozenAutomaticLanguage
        decisions = model.decode(active, after: previous, previousEndedSentence: previousEndedSentence,
                                 sentenceEnds: separators.map(Self.endsSentence))
        automatic = ""
        suggestion = ""
        for (index, decision) in decisions.enumerated() {
            let word = active[index]
            suggestion += (decision == .keep ? word.typed : word.mapped) + separators[index]
            automatic += (decision == .automatic ? word.mapped : word.typed) + separators[index]
            if decision != .keep { language = word.source }
            if decision == .automatic { automaticLanguage = word.source }
        }
    }
}
