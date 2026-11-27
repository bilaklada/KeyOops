import AppKit
import ApplicationServices
import KeyOopsCore
import MacLayouts

/// Exercise the production AX adapter and guarded edit in a real, frontmost
/// control containing only the public fixture. No keyboard injection or clipboard.
@MainActor func run() throws {
    let args = CommandLine.arguments
    guard AXIsProcessTrusted() else {
        print("BLOCKED: macOS Accessibility permission is missing for the host verifier.")
        exit(77)
    }
    guard args.count == 3, ["roundtrip", "isolation"].contains(args[1]) else {
        print("Usage: VerifyHost roundtrip|isolation <host bundle identifier>")
        exit(64)
    }
    let sample = "KeyOops QA. цу all enjoy a little bit of poetry. руку фку ыщьу ща еру иуые сдфыышсфд зщуекн. цу all enjoy. "
    let expected = "KeyOops QA. we all enjoy a little bit of poetry. here are some of the best classical poetry. we all enjoy. "
    func matches(_ editor: FocusedEditor, _ value: String) -> Bool {
        guard editor.focused, editor.bundle == args[2], editor.characterCount == value.utf16.count,
              let selection = editor.selection, selection.location == value.utf16.count, selection.length == 0 else { return false }
        return editor.text(CFRange(location: 0, length: value.utf16.count)) == value
    }
    func fail(_ message: String) -> Never { print("FAIL: \(message)"); exit(1) }
    print("Focus the prepared \(args[2]) field with its caret at the end (30 seconds).")
    let deadline = Date().addingTimeInterval(30)
    var target: FocusedEditor?
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == args[2],
           let editor = FocusedEditor.current(), matches(editor, sample) { target = editor; break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard let editor = target else { fail("No capable focused field matched the exact fixture and caret.") }
    final class Binding {
        let editor: FocusedEditor
        init(_ editor: FocusedEditor) { self.editor = editor }
    }
    let binding = Binding(editor)
    var observer: AXObserver?
    guard AXObserverCreate(editor.pid, { _, _, _, context in
        guard let context else { return }
        MainActor.assumeIsolated { Unmanaged<Binding>.fromOpaque(context).takeUnretainedValue().editor.invalidate() }
    }, &observer) == .success, let observer,
          editor.registerInvalidation(on: observer, context: Unmanaged.passUnretained(binding).toOpaque()) else {
        fail("Host cannot provide the required lifetime notifications.")
    }
    let source = AXObserverGetRunLoopSource(observer)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    defer { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); withExtendedLifetime(binding) {} }
    guard let model = PhraseModel.bundled else { fail("Model missing") }
    let pair = try SystemLayouts.pair()
    let passage = EditorPassage(editor: editor, start: 0, model: model, english: pair.english, russian: pair.russian)
    var timings = [UInt64]()
    for _ in 0..<25 {
        let start = DispatchTime.now().uptimeNanoseconds
        guard passage.refresh(), let edit = passage.edit(automatic: false, accepting: true),
              edit.preview != nil, let selection = editor.selection else { fail("Preview rejected") }
        _ = editor.bounds(selection)
        timings.append(DispatchTime.now().uptimeNanoseconds - start)
    }
    print("AX refresh, preview and caret bounds p95: \(timings.sorted()[23] / 1000) µs")
    guard let edit = passage.edit(automatic: false, accepting: true) else { fail("No accumulated suggestion") }
    if args[1] == "isolation" {
        print("Switch to a second fixture field, tab, window, or navigated document with identical text and caret.")
        let timeout = Date().addingTimeInterval(30)
        while Date() < timeout {
            if let next = FocusedEditor.current(), matches(next, sample), !editor.focused {
                guard edit.preview == nil, !edit.apply(), matches(next, sample) else { fail("Stale edit survived") }
                print("PASS: stale edit refused in second fixture.")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        fail("Did not observe two distinct focused fixture controls.")
    }
    for automatic in [false, true] {
        guard matches(editor, sample), passage.refresh(),
              let correction = passage.edit(automatic: automatic, accepting: !automatic),
              correction.apply(), matches(editor, expected) else { fail("Correction or post-write verification") }
        guard correction.reversed.apply(), matches(editor, sample) else { fail("Undo verification") }
    }
    print("PASS: suggestion, automatic correction, caret and undo through the host's AX control.")
}
try run()
