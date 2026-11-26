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
    private let replacement: String

    public init(editor: any LiveTextEditor, language: LayoutLanguage, start: Int,
                original: String, replacement: String) {
        self.editor = editor
        self.language = language
        self.start = start
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
        let caret = CFRange(location: start + range.length, length: 0)
        guard ownsSelection(caret), editor.text(range) == original else { return nil }
        return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func apply() -> Bool {
        let range = CFRange(location: start, length: original.utf16.count)
        let caret = CFRange(location: start + range.length, length: 0)
        guard ownsSelection(caret), editor.text(range) == original, editor.select(range),
              ownsSelection(range) else { return false }
        guard editor.text(range) == original, editor.replaceSelection(with: replacement) else {
            // A host may move focus or change the user's selection during a failed write.
            // Restore the caret only while our temporary selection is still in place.
            if ownsSelection(range) { _ = editor.select(caret) }
            return false
        }
        let written = CFRange(location: start, length: replacement.utf16.count)
        if editor.focused && editor.text(written) == replacement { return true }
        if ownsSelection(range), editor.text(range) == original { _ = editor.select(caret) }
        return false
    }

    public var reversed: Self {
        Self(editor: editor, language: language.opposite, start: start,
             original: replacement, replacement: original)
    }
}
