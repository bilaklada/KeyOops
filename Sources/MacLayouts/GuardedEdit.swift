import Foundation
import KeyOopsCore

@MainActor public protocol LiveTextEditor {
    var focused: Bool { get }
    var selection: CFRange? { get }
    func text(_ range: CFRange) -> String?
    func select(_ range: CFRange) -> Bool
    func replaceSelection(with text: String) -> Bool
}

@MainActor public struct GuardedEdit {
    private let editor: any LiveTextEditor
    public let language: LayoutLanguage
    private let start: Int
    private let original: String
    private let tail: String
    private let replacement: String

    public init(editor: any LiveTextEditor, language: LayoutLanguage, start: Int,
                original: String, replacement: String, trailingContext: String = "") {
        self.editor = editor
        self.language = language
        self.start = start
        self.tail = trailingContext
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
        let caret = CFRange(location: start + range.length + tail.utf16.count, length: 0)
        guard ownsSelection(caret), matchesOriginal else { return nil }
        return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchesOriginal: Bool {
        editor.text(CFRange(location: start, length: original.utf16.count + tail.utf16.count)) == original + tail
    }

    public func apply() -> Bool {
        let range = CFRange(location: start, length: original.utf16.count)
        let caret = CFRange(location: start + range.length + tail.utf16.count, length: 0)
        guard ownsSelection(caret), matchesOriginal, editor.select(range),
              ownsSelection(range) else { return false }
        guard matchesOriginal, editor.replaceSelection(with: replacement) else {
            // A host may move focus or change the user's selection during a failed write.
            // Restore the caret only while our temporary selection is still in place.
            if ownsSelection(range) { _ = editor.select(caret) }
            return false
        }
        let written = CFRange(location: start, length: replacement.utf16.count)
        if editor.focused && editor.text(written) == replacement {
            let insertedEnd = CFRange(location: start + written.length, length: 0)
            if !tail.isEmpty, ownsSelection(insertedEnd),
               editor.text(CFRange(location: insertedEnd.location, length: tail.utf16.count)) == tail {
                _ = editor.select(CFRange(location: insertedEnd.location + tail.utf16.count, length: 0))
            }
            return true
        }
        if ownsSelection(range), matchesOriginal { _ = editor.select(caret) }
        return false
    }

    public var reversed: Self {
        Self(editor: editor, language: language.opposite, start: start,
             original: replacement, replacement: original, trailingContext: tail)
    }
}
