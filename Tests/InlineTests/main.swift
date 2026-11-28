import AppKit
import Carbon

@MainActor func verify() {
    func event(_ code: Int, _ flags: CGEventFlags = []) -> CGEvent {
        let key = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        key.flags = flags
        return key
    }
    precondition(InlineSuggestion.shortcut(event(kVK_Tab)) == true)
    precondition(InlineSuggestion.shortcut(event(kVK_Escape)) == false)
    for (key, flags) in [(kVK_Tab, CGEventFlags.maskShift), (kVK_Tab, .maskControl),
                         (kVK_Escape, .maskCommand), (kVK_ANSI_A, CGEventFlags())] {
        precondition(InlineSuggestion.shortcut(event(key, flags)) == nil)
    }
    precondition(InlineSuggestion.shortcut(event(kVK_Tab), optionSpace: true) == nil)
    precondition(InlineSuggestion.shortcut(event(kVK_Space, .maskAlternate), optionSpace: true) == true)
    precondition(InlineSuggestion.shortcut(event(kVK_Space, .maskAlternate)) == nil)
    precondition(InlineSuggestion.shortcut(event(kVK_Space, [.maskAlternate, .maskShift]), optionSpace: true) == nil)
    precondition(InlineSuggestion.shortcut(event(kVK_Escape), optionSpace: true) == false)
    let repeated = event(kVK_Tab)
    repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
    precondition(InlineSuggestion.shortcut(repeated) == nil)
    print("Inline shortcut checks passed.")
    let overlay = InlineSuggestion()
    guard let screen = NSScreen.screens.first else { return }
    let visible = screen.visibleFrame
    for anchor in [CGPoint(x: visible.midX, y: visible.midY),
                   CGPoint(x: visible.maxX - 2, y: visible.minY + 2)] {
        overlay.display("My name is Анна", anchor: anchor, caretHeight: 18, screen: screen)
        guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) else {
            fatalError("Missing inline preview")
        }
        precondition(!panel.isKeyWindow && panel.frame.width > 60 && panel.frame.height >= 20)
        precondition(visible.contains(panel.frame))
        overlay.hide()
        precondition(!panel.isVisible)
    }
    let caret = CGRect(x: visible.midX, y: screen.frame.maxY - visible.midY, width: 1, height: 18)
    overlay.show("hello", at: caret, optionSpace: true, previewOnly: true) { _ in
        fatalError("Display-only previews must never invoke an edit")
    }
    precondition(overlay.panelVisible)
    let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }
    let label = panel?.contentView?.subviews.compactMap { $0 as? NSTextField }.first
    precondition(label?.stringValue == "hello    Preview only")
    overlay.hide()
    print("Nonactivating preview placement and dismissal passed.")
}
MainActor.assumeIsolated {
    _ = NSApplication.shared
    verify()
}
