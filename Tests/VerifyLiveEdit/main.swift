import AppKit
import MacLayouts

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

    let typed = EditorFixture()
    typed.view.insertText("x", replacementRange: typed.view.selectedRange())
    precondition(!typed.edit.apply() && typed.view.string == "🌍 ghbdtn x")

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
