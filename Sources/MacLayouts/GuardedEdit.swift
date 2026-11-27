import Foundation
import KeyOopsCore

@MainActor public protocol LiveTextEditor {
    var focused: Bool { get }
    var selection: CFRange? { get }
    var characterCount: Int? { get }
    func text(_ range: CFRange) -> String?
    func select(_ range: CFRange) -> Bool
    func replaceSelection(with text: String) -> Bool
}

@MainActor public struct GuardedEdit {
    private let editor: any LiveTextEditor
    public let language: LayoutLanguage
    private let start: Int
    private let original: String
    private let leading: String
    private let gap: Int
    private let tail: String
    private let replacement: String

    public init(editor: any LiveTextEditor, language: LayoutLanguage, start: Int,
                original: String, replacement: String, trailingContext: String = "",
                untrackedTailLength: Int = 0, leadingContext: String = "") {
        self.editor = editor
        self.language = language
        self.start = start
        self.tail = trailingContext
        self.leading = leadingContext
        self.gap = untrackedTailLength
        self.original = original
        self.replacement = replacement
    }

    private func ownsSelection(_ range: CFRange) -> Bool {
        guard editor.focused, let selected = editor.selection else { return false }
        return selected.location == range.location && selected.length == range.length
    }

    /// A menu opened after a caret or focus change must not reveal the old proposal.
    public var preview: String? {
        let range = CFRange(location: start, length: original.utf16.count)
        let caret = CFRange(location: start + range.length + tail.utf16.count + gap, length: 0)
        guard ownsSelection(caret), matchesOriginal else { return nil }
        return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchesOriginal: Bool {
        let expected = leading + original + tail
        guard let text = editor.text(CFRange(location: start - leading.utf16.count, length: expected.utf16.count)) else { return false }
        return text.utf16.elementsEqual(expected.utf16)
    }

    public func apply() -> Bool {
        let range = CFRange(location: start, length: original.utf16.count)
        let caret = CFRange(location: start + range.length + tail.utf16.count + gap, length: 0)
        guard ownsSelection(caret), matchesOriginal, editor.select(range),
              ownsSelection(range) else { return false }
        guard matchesOriginal, ownsSelection(range), editor.replaceSelection(with: replacement) else {
            // A host may move focus or change the user's selection during a failed write.
            // Restore the caret only while our temporary selection is still in place.
            if ownsSelection(range) { _ = editor.select(caret) }
            return false
        }
        let written = CFRange(location: start, length: replacement.utf16.count)
        if editor.focused && editor.text(written) == replacement {
            let insertedEnd = CFRange(location: start + written.length, length: 0)
            if (!tail.isEmpty || gap > 0), ownsSelection(insertedEnd),
               editor.text(CFRange(location: insertedEnd.location, length: tail.utf16.count)) == tail {
                _ = editor.select(CFRange(location: insertedEnd.location + tail.utf16.count + gap, length: 0))
            }
            return true
        }
        if ownsSelection(range), matchesOriginal { _ = editor.select(caret) }
        return false
    }

    public var reversed: Self {
        Self(editor: editor, language: language.opposite, start: start,
             original: replacement, replacement: original, trailingContext: tail,
             untrackedTailLength: gap, leadingContext: leading)
    }
}
