import AppKit
import ApplicationServices
import Carbon
import KeyOopsCore
import MacLayouts

/// macOS text offsets are UTF-16 units. Keep the exact inspected range for the
/// reply so an edit, focus change or selection change invalidates it.
@MainActor private struct Editor: LiveTextEditor {
    let element: AXUIElement
    let pid: pid_t

    static func current() -> Self? {
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              ["com.apple.TextEdit", "com.apple.Notes"].contains(app.bundleIdentifier),
              let element = attribute(AXUIElementCreateApplication(app.processIdentifier),
                                      kAXFocusedUIElementAttribute) else { return nil }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let field = element as! AXUIElement
        guard attribute(field, kAXRoleAttribute) as? String == kAXTextAreaRole,
              attribute(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        var editable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &editable) == .success,
              editable.boolValue else { return nil }
        return Self(element: field, pid: app.processIdentifier)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    var selection: CFRange? {
        guard let raw = Self.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        return range
    }

    func rangeValue(_ range: CFRange) -> AXValue? {
        var copy = range
        return AXValueCreate(.cfRange, &copy)
    }

    func text(_ range: CFRange) -> String? {
        guard let value = rangeValue(range) else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                kAXStringForRangeParameterizedAttribute as CFString, value, &text) == .success else { return nil }
        return text as? String
    }

    func select(_ range: CFRange) -> Bool {
        guard let value = rangeValue(range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func replaceSelection(with text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    var focused: Bool {
        guard let current = Self.current() else { return false }
        return pid == current.pid && CFEqual(element, current.element)
    }
}

@MainActor final class LiveCorrection {
    enum Mode: String, CaseIterable { case off = "Off", suggest = "Suggest", automatic = "Automatic" }
    var changed: () -> Void = {}
    private(set) var mode = Mode.off
    private(set) var status = "Selected text only"
    private var monitor: Any?
    private var pending: GuardedEdit?
    private var undo: GuardedEdit?
    private var editEnd: (editor: Editor, offset: Int)?
    // Only the field identity and UTF-16 offset survive a dismissal or undo.
    private var ignoredThrough: (editor: Editor, offset: Int)?
    private var switchedLayout = false
    private var expiry: Task<Void, Never>?
    private var boundary: Task<Void, Never>?
    var canAccept: Bool { pending != nil }
    var canUndo: Bool { undo != nil }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetContext),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetContext),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetContext),
            name: NSWorkspace.willSleepNotification, object: nil)
    }

    func set(_ next: Mode, prompt: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        mode = .off
        resetContext()
        guard next != .off else { return }
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary),
              CGPreflightListenEventAccess() || (prompt && CGRequestListenEventAccess()) else {
            status = "Allow Accessibility and Input Monitoring, then retry"
            changed()
            return
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.boundary?.cancel()
                guard event.type == .keyDown else { return }
                if self.pending != nil || self.undo != nil { self.clear() }
                guard event.keyCode == UInt16(kVK_Space),
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      !event.isARepeat, !IsSecureEventInputEnabled(),
                      let editor = Editor.current() else { return }
                // The host must commit the space before we inspect its caret.
                self.boundary = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(45))
                    guard !Task.isCancelled, editor.focused else { return }
                    self.inspect(editor)
                }
            }
        }
        mode = monitor == nil ? .off : next
        clear()
    }

    @objc private func resetContext() {
        ignoredThrough = nil
        clear()
    }

    func dismiss() {
        ignoredThrough = editEnd
        clear()
    }

    private func clear() {
        editEnd = nil
        expiry?.cancel()
        boundary?.cancel()
        pending = nil
        undo = nil
        switchedLayout = false
        status = mode == .off ? "Selected text only" : "\(mode.rawValue) · TextEdit and Notes"
        changed()
    }

    private func inspect(_ editor: Editor) {
        guard let caret = editor.selection, caret.length == 0, caret.location > 1 else { return }
        var floor = 0
        if let ignoredThrough, CFEqual(ignoredThrough.editor.element, editor.element),
           ignoredThrough.editor.pid == editor.pid, ignoredThrough.offset <= caret.location {
            floor = ignoredThrough.offset
        } else {
            ignoredThrough = nil
        }
        let length = min(LayoutProposal.inspectionLength, caret.location - floor)
        guard length > 1 else { return }
        guard let suffix = editor.text(CFRange(location: caret.location - length, length: length)),
              let pair = try? SystemLayouts.pair(),
              let proposal = LayoutProposal.ending(in: suffix, atDocumentStart: caret.location - floor == length,
                                                   english: pair.english, russian: pair.russian) else { return }
        clear()
        editEnd = (editor, caret.location)
        let edit = GuardedEdit(editor: editor, language: proposal.language,
                               start: caret.location - proposal.original.utf16.count - 1,
                               original: proposal.original + " ", replacement: proposal.replacement + " ")
        if mode == .automatic && proposal.decision == .automatic {
            guard edit.apply() else { return }
            switchedLayout = SystemLayouts.switchAfterCorrection(from: edit.language)
            undo = edit.reversed
            status = "Layout corrected · Undo available"
        } else {
            pending = edit
            status = "Layout suggestion available"
        }
        expire()
        changed()
    }

    func accept() {
        guard let edit = pending else { return }
        let end = editEnd
        clear()
        if edit.apply() {
            editEnd = end
            switchedLayout = SystemLayouts.switchAfterCorrection(from: edit.language)
            undo = edit.reversed
            status = "Layout corrected · Undo available"
            expire()
            changed()
        }
    }

    func undoLast() {
        let edit = undo
        let end = editEnd
        let restoreLayout = switchedLayout
        clear()
        if let edit, edit.apply() {
            ignoredThrough = end
            if restoreLayout { _ = SystemLayouts.switchAfterCorrection(from: edit.language) }
        }
    }

    private func expire() {
        expiry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { clear() }
        }
    }
}
