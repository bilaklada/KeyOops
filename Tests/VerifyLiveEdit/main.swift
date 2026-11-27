import AppKit
import MacLayouts
import KeyOopsCore

/// Use an actual AppKit text view for UTF-16 selection and replacement semantics.
@MainActor final class EditorFixture: LiveTextEditor {
    let view = NSTextView()
    var focused = true
    var afterSelect: (() -> Void)?
    var write: ((String) -> Bool)?

    init() {
        view.string = "🌍 ghbdtn "
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    }

    var characterCount: Int? { view.string.utf16.count }

    var selection: CFRange? {
        let range = view.selectedRange()
        return CFRange(location: range.location, length: range.length)
    }

    func text(_ range: CFRange) -> String? {
        guard range.location + range.length <= view.string.utf16.count else { return nil }
        return (view.string as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }

    func select(_ range: CFRange) -> Bool {
        view.setSelectedRange(NSRange(location: range.location, length: range.length))
        afterSelect?()
        return true
    }

    func replaceSelection(with text: String) -> Bool {
        if let write { return write(text) }
        view.insertText(text, replacementRange: view.selectedRange())
        return true
    }

    var edit: GuardedEdit {
        GuardedEdit(editor: self, language: .english, start: 3, original: "ghbdtn ", replacement: "привет ")
    }
}

@MainActor func verify() {
    let editor = EditorFixture()
    precondition(editor.edit.preview == "привет")
    precondition(editor.edit.apply() && editor.view.string == "🌍 привет ")
    precondition(editor.edit.reversed.apply() && editor.view.string == "🌍 ghbdtn ")

    let mixed = EditorFixture()
    mixed.view.string = "Ьн name is "
    mixed.view.setSelectedRange(NSRange(location: 11, length: 0))
    let prefix = GuardedEdit(editor: mixed, language: .russian, start: 0, original: "Ьн",
                             replacement: "My", trailingContext: " name is ")
    precondition(prefix.apply() && mixed.view.string == "My name is ")
    precondition(mixed.view.selectedRange().location == 11 && prefix.reversed.apply())
    mixed.view.string = "Ьн game is "
    mixed.view.setSelectedRange(NSRange(location: 11, length: 0))
    precondition(prefix.preview == nil && !prefix.apply())

    let typed = EditorFixture()
    typed.view.insertText("x", replacementRange: typed.view.selectedRange())
    precondition(!typed.edit.apply() && typed.view.string == "🌍 ghbdtn x")

    func layout(_ row: String) -> KeyboardLayout {
        var keys: [PhysicalKey: Character] = [:]
        for (i, c) in row.enumerated() { keys[PhysicalKey(code: UInt16(i), shifted: false)] = c }
        return KeyboardLayout(outputs: keys)
    }
    let en = layout("qwertyuiopasdfghjklzxcvbnm"), ru = layout("йцукенгшщзфывапролдячсмить")
    func session(_ editor: EditorFixture) -> EditorPassage {
        EditorPassage(editor: editor, start: 0, model: PhraseModel.bundled!, english: en, russian: ru)
    }
    let document = EditorFixture()
    document.view.string = "цу all enjoy. "
    document.view.setSelectedRange(NSRange(location: document.view.string.utf16.count, length: 0))
    let passage = session(document)
    precondition(passage.refresh())
    document.view.insertText("руку фку ыщьу. unfinished", replacementRange: document.view.selectedRange())
    precondition(passage.refresh())
    let batch = passage.edit(automatic: false)!
    let original = document.view.string
    document.focused = false
    let other = EditorFixture()
    other.view.string = original
    other.view.setSelectedRange(document.view.selectedRange())
    precondition(!passage.refresh() && !batch.apply() && other.view.string == original)
    document.focused = true
    precondition(batch.apply() && document.view.string == "we all enjoy. here are some. unfinished")
    precondition(document.view.selectedRange().location == document.view.string.utf16.count)
    precondition(batch.reversed.apply() && document.view.string == original)
    document.view.string = "xx" + original.dropFirst(2)
    document.view.setSelectedRange(NSRange(location: original.utf16.count, length: 0))
    precondition(!passage.refresh() && !batch.apply())

    let review = EditorFixture()
    review.view.string = "цу all enjoy. руку фку ыщьу."
    review.view.setSelectedRange(NSRange(location: review.view.string.utf16.count, length: 0))
    let completed = session(review)
    precondition(completed.refresh() && completed.edit(automatic: false, accepting: true)!.apply())
    precondition(review.view.string == "we all enjoy. here are some.")

    let declined = EditorFixture()
    declined.view.string = "цу all enjoy. "
    declined.view.setSelectedRange(NSRange(location: declined.view.string.utf16.count, length: 0))
    let firstBatch = session(declined)
    precondition(firstBatch.refresh() && firstBatch.edit(automatic: false) != nil)
    let nextBatch = EditorPassage(editor: declined, start: firstBatch.end, model: PhraseModel.bundled!,
                                  english: en, russian: ru)
    declined.view.insertText("good morning ", replacementRange: declined.view.selectedRange())
    precondition(nextBatch.refresh() && nextBatch.edit(automatic: false) == nil)
    precondition(declined.view.string.hasPrefix("цу "))

    let overflow = EditorFixture()
    overflow.view.string = "цу all enjoy. " + String(repeating: "x", count: TypingPassage.capacity)
    overflow.view.setSelectedRange(NSRange(location: overflow.view.string.utf16.count, length: 0))
    let capped = session(overflow)
    precondition(capped.refresh() && capped.full)
    precondition(capped.edit(automatic: false)!.apply())
    precondition(overflow.view.string.hasPrefix("we all enjoy.") &&
                 overflow.view.selectedRange().location == overflow.view.string.utf16.count)

    let jump = EditorFixture()
    jump.view.string = "цу all enjoy. existing text"
    jump.view.setSelectedRange(NSRange(location: 14, length: 0))
    let anchored = session(jump)
    precondition(anchored.refresh())
    jump.view.setSelectedRange(NSRange(location: jump.view.string.utf16.count, length: 0))
    precondition(!anchored.refresh())

    let moved = EditorFixture()
    moved.view.setSelectedRange(NSRange(location: 0, length: 0))
    precondition(moved.edit.preview == nil)
    precondition(!moved.edit.apply() && moved.view.selectedRange().location == 0)

    let switched = EditorFixture()
    switched.afterSelect = { switched.focused = false }
    precondition(!switched.edit.apply() && switched.view.string == "🌍 ghbdtn ")

    let failed = EditorFixture()
    failed.write = { _ in false }
    precondition(!failed.edit.apply() && failed.view.selectedRange() == NSRange(location: 10, length: 0))

    let interrupted = EditorFixture()
    interrupted.write = { _ in
        interrupted.view.setSelectedRange(NSRange(location: 0, length: 2))
        return false
    }
    precondition(!interrupted.edit.apply() && interrupted.view.selectedRange() == NSRange(location: 0, length: 2))

    let ignored = EditorFixture()
    ignored.write = { _ in true }
    precondition(!ignored.edit.apply() && ignored.view.selectedRange() == NSRange(location: 10, length: 0))
}
_ = NSApplication.shared
verify()
print("AppKit live-edit checks passed.")
