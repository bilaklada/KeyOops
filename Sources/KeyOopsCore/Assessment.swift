/// A small, inspectable vocabulary for the preview label. Manual conversion
/// remains available when neither reading has enough evidence.
public enum Assessment {
    private static let english: Set<String> = [
        "hello", "world", "good", "morning", "thanks", "please", "meeting",
        "tomorrow", "today", "keyboard", "layout", "message", "friend", "test"
    ]
    private static let russian: Set<String> = [
        "привет", "мир", "доброе", "утро", "спасибо", "пожалуйста", "встреча",
        "завтра", "сегодня", "клавиатура", "раскладка", "сообщение", "друг", "тест"
    ]

    public static func suggests(original: String, candidate: String, source: LayoutLanguage) -> Bool {
        let before = original.lowercased().split { !$0.isLetter }
        let after = candidate.lowercased().split { !$0.isLetter }
        let knownSource = source == .english ? english : russian
        let knownTarget = source == .english ? russian : english
        return !after.isEmpty && before.count == after.count
            && before.allSatisfy { !knownSource.contains(String($0)) }
            && after.allSatisfy { knownTarget.contains(String($0)) }
    }
}
