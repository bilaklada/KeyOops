import Foundation
import KeyOopsCore

/// One append-only range in one editor. The editor's focused property verifies
/// the application, window, document and field again during every transaction.
@MainActor public final class EditorPassage {
    private let editor: any LiveTextEditor
    private let model: PhraseModel
    private let english: KeyboardLayout
    private let russian: KeyboardLayout
    public let start: Int
    private var passage: TypingPassage
    private var rightLength: Int?
    private var rightText: String?
    private var caret: Int
    public private(set) var full = false

    public init(editor: any LiveTextEditor, start: Int, model: PhraseModel,
                english: KeyboardLayout, russian: KeyboardLayout) {
        let prefix = start > 0 && editor.focused ? editor.text(CFRange(location: start - 1, length: 1)) : nil
        passage = TypingPassage(continuingWord: start > 0 && prefix?.last?.isWhitespace != true)
        self.editor = editor
        self.start = start
        self.caret = start
        self.model = model
        self.english = english
        self.russian = russian
    }

    public var end: Int { caret }

    public func refresh() -> Bool {
        guard editor.focused, let selection = editor.selection, selection.length == 0,
              selection.location >= caret else { return false }
        guard let count = editor.characterCount, count >= selection.location else { return false }
        // Appending at the caret leaves both the length and start of the text
        // to its right intact. A programmatic caret jump can otherwise resemble typing.
        let remaining = count - selection.location
        guard rightLength == nil || rightLength == remaining else { return false }
        let right = remaining == 0 ? "" : editor.text(CFRange(location: selection.location, length: min(remaining, 32)))
        guard let right else { return false }
        if let rightText, !right.utf16.elementsEqual(rightText.utf16) { return false }
        rightLength = remaining
        rightText = right
        let length = min(selection.location - start, TypingPassage.capacity)
        guard let text = editor.text(CFRange(location: start, length: length)),
              text.utf16.count == length, text.utf16.starts(with: passage.original.utf16),
              editor.focused, let current = editor.selection, current.length == 0,
              current.location == selection.location else { return false }
        let newText = text.utf16.dropFirst(passage.original.utf16.count)
        guard passage.append(String(decoding: newText, as: UTF16.self), model: model,
                             english: english, russian: russian) else { return false }
        caret = selection.location
        full = length == TypingPassage.capacity
        return true
    }

    public func edit(automatic: Bool, accepting: Bool = false) -> GuardedEdit? {
        let original = passage.original
        var projection = passage
        // At explicit acceptance, punctuation completes the final word even if
        // the writer has not entered a space. Never complete a partial bare word.
        let terminated = accepting && original.last.map { ".!?…".contains($0) } == true &&
            projection.append(" ", model: model, english: english, russian: russian)
        var replacement = automatic ? projection.automaticText : projection.suggestedText
        if terminated { replacement.removeLast() }
        guard original != replacement,
              let language = automatic ? projection.automaticLanguage : projection.language else { return nil }
        // Trim whole characters so an edit never splits a surrogate or combining sequence.
        var prefix = 0
        for (a, b) in zip(original, replacement) {
            guard a == b else { break }
            prefix += 1
        }
        let before = original.dropFirst(prefix), after = replacement.dropFirst(prefix)
        var suffix = 0
        for (a, b) in zip(before.reversed(), after.reversed()) {
            guard a == b else { break }
            suffix += 1
        }
        return GuardedEdit(editor: editor, language: language,
                           start: start + original.prefix(prefix).utf16.count,
                           original: String(before.dropLast(suffix)), replacement: String(after.dropLast(suffix)),
                           trailingContext: String(before.suffix(suffix)),
                           untrackedTailLength: caret - start - original.utf16.count,
                           leadingContext: String(original.prefix(prefix)))
    }

    /// Retain earlier unresolved words after an automatic correction. Physical-key
    /// edits may differ in UTF-16 length, so take the next caret from the host.
    public func resumeAfterAutomaticEdit() -> Bool {
        passage.commitAutomatic(model: model, english: english, russian: russian)
        caret = start
        return refresh()
    }
}
