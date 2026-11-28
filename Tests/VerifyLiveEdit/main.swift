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

    for id in ["com.apple.Terminal", "com.agilebits.onepassword7", "com.apple.SecurityAgent",
               "com.apple.Passwords", "com.bitwarden.desktop", "com.mitchellh.ghostty"] {
        precondition(!LiveHostPolicy.enabled(id))
    }
    precondition(!LiveHostPolicy.enabled(nil))
    precondition(LiveHostPolicy.textControl(role: "AXComboBox", editable: nil))
    precondition(LiveHostPolicy.textControl(role: "AXGroup", editable: true))
    precondition(!LiveHostPolicy.textControl(role: "AXGroup", editable: nil))
    precondition(!LiveHostPolicy.textControl(role: "AXTextArea", editable: false))
    precondition(!LiveHostPolicy.textControl(role: "AXWebArea", editable: true))
    precondition(LiveHostPolicy.excludesControl(subrole: nil, classes: ["monaco-editor"]))
    precondition(LiveHostPolicy.excludesControl(subrole: "AXSourceEditor", classes: []))
    precondition(LiveHostPolicy.excludesControl(subrole: "AXSecureTextField", classes: []))
    precondition(LiveHostPolicy.excludesControl(subrole: nil, classes: ["xterm-helper-textarea"]))
    for id in ["com.microsoft.VSCode", "com.jetbrains.intellij", "com.apple.iWork.Numbers"] {
        precondition(LiveHostPolicy.enabled(id) && LiveHostPolicy.usesOptionSpace(id))
    }
    precondition(!LiveHostPolicy.usesOptionSpace("com.google.Chrome"))
    // Hold all text and caret data constant. Each ownership component must
    // independently prevent equality, including a duplicate URL in two tabs.
    func identity(pid: pid_t = 1, window: Int = 2, field: Int = 3, area: Int = 4,
                  path: String = "a", document: String = "draft") -> EditorIdentity<Int> {
        EditorIdentity(pid: pid, window: window, field: field, document: document,
                       ancestry: [.init(area: area, url: URL(fileURLWithPath: "/" + path))])
    }
    for other in [identity(pid: 2), identity(window: 3), identity(field: 4), identity(area: 5),
                  identity(path: "b"), identity(document: "another draft")] {
        precondition(identity() != other)
    }
    let embedded = EditorIdentity<Int>.Document(area: 1, url: nil)
    precondition(embedded != .init(area: 2, url: nil))
    precondition(embedded != .init(area: 1, url: URL(string: "about:blank")))
    precondition(LiveHostPolicy.reservesTab(role: "AXCell", classes: []))
    precondition(!LiveHostPolicy.reservesTab(role: "AXTextArea", classes: []))
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

    let partial = EditorFixture()
    partial.view.string = "unfinished"
    partial.view.setSelectedRange(NSRange(location: partial.view.string.utf16.count, length: 0))
    let continuation = EditorPassage(editor: partial, start: partial.view.string.utf16.count,
                                     model: PhraseModel.bundled!, english: en, russian: ru)
    partial.view.insertText("руддщ ", replacementRange: partial.view.selectedRange())
    precondition(continuation.refresh() && continuation.edit(automatic: false) == nil)

    let overflow = EditorFixture()
    overflow.view.string = "цу all enjoy. " + String(repeating: "x", count: TypingPassage.capacity)
    overflow.view.setSelectedRange(NSRange(location: overflow.view.string.utf16.count, length: 0))
    let capped = session(overflow)
    precondition(capped.refresh() && capped.full)
    precondition(capped.edit(automatic: false)!.apply())
    precondition(overflow.view.string.hasPrefix("we all enjoy.") &&
                 overflow.view.selectedRange().location == overflow.view.string.utf16.count)

    let long = EditorFixture()
    long.view.string = String(repeating: "good morning. ", count: 270) + "цу all enjoy. "
    long.view.setSelectedRange(NSRange(location: long.view.string.utf16.count, length: 0))
    let longSession = session(long)
    precondition(longSession.refresh())
    var refreshTimes = [UInt64]()
    for _ in 0..<96 {
        long.view.insertText("x", replacementRange: long.view.selectedRange())
        let tick = DispatchTime.now().uptimeNanoseconds
        precondition(longSession.refresh() && longSession.edit(automatic: false)?.preview == "we")
        refreshTimes.append(DispatchTime.now().uptimeNanoseconds - tick)
    }
    print("AppKit long-session refresh and preview p95 \(refreshTimes.sorted()[refreshTimes.count * 95 / 100] / 1000) µs")

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
