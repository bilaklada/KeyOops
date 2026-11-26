/// Extract one completed token from the bounded Accessibility suffix. A token
/// touching a truncated left edge might be the tail of a longer identifier.
public enum CompletedWord {
    public static let maximumUTF16Length = 48
    public static let inspectionLength = maximumUTF16Length + 3

    public static func read(suffix: String, startsAtDocumentBeginning: Bool) -> String? {
        guard suffix.last == " ", suffix.utf16.count <= inspectionLength else { return nil }
        let before = suffix.dropLast()
        let word = String(before.reversed().prefix { !$0.isWhitespace }.reversed())
        guard !word.isEmpty, word.utf16.count <= maximumUTF16Length,
              word.count < before.count || startsAtDocumentBeginning else { return nil }
        return word
    }
}
