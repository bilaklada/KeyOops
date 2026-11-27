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
    let window: AXUIElement
    let document: String?
    let noteMarker: CFTypeRef?

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
        guard let rawWindow = attribute(field, kAXWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = rawWindow as! AXUIElement
        let isNotes = app.bundleIdentifier == "com.apple.Notes"
        let fieldDocument = attribute(field, kAXDocumentAttribute) as? String
        let document = fieldDocument ?? (isNotes ? nil : attribute(window, kAXDocumentAttribute) as? String)
        // Notes can reuse a window and text area for consecutive notes. Bind
        // the session to a document identifier or a host-issued text marker.
        var noteMarker: CFTypeRef?
        if isNotes && document == nil {
            guard AXUIElementCopyParameterizedAttributeValue(field, "AXTextMarkerForIndex" as CFString,
                    0 as CFNumber, &noteMarker) == .success, noteMarker != nil else { return nil }
        }
        return Self(element: field, pid: app.processIdentifier, window: window, document: document, noteMarker: noteMarker)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    var characterCount: Int? { (Self.attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue }

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

    func bounds(_ range: CFRange) -> CGRect? {
        guard let value = rangeValue(range) else { return nil }
        var raw: CFTypeRef?
        var rect = CGRect.zero
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                  value, &raw) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID(),
              AXValueGetValue(raw as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return rect
    }

    func select(_ range: CFRange) -> Bool {
        guard focused, let value = rangeValue(range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func replaceSelection(with text: String) -> Bool {
        focused && AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    var focused: Bool {
        guard let current = Self.current() else { return false }
        guard pid == current.pid, CFEqual(window, current.window), CFEqual(element, current.element),
              document == current.document else { return false }
        guard let noteMarker else { return true }
        var index: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(current.element, "AXIndexForTextMarker" as CFString,
            noteMarker, &index) == .success && ((index as? NSNumber)?.intValue ?? -1) >= 0
    }
}

@MainActor final class LiveCorrection {
    enum Mode: String, CaseIterable { case off = "Off", suggest = "Suggest", automatic = "Automatic" }
    var changed: () -> Void = {}
    private(set) var mode = Mode.off
    private(set) var status = "Selected text only"
    private let inline = InlineSuggestion()
    private var model: PhraseModel?
    private var loading = false
    private var monitor: Any?
    private var observer: AXObserver?
    private var owner: Editor?
    private var session: EditorPassage?
    private var pending: GuardedEdit?
    private var undo: GuardedEdit?
    private var switchedLayout = false
    private var boundary: Task<Void, Never>?
    private var floor = 0
    private var menuState = ""
    var canAccept: Bool { pending != nil }
    var canUndo: Bool { undo != nil }
    var suggestionPreview: String? {
        guard session?.refresh() == true else { return nil }
        return session?.edit(automatic: false, accepting: true)?.preview
    }

    init() {
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetContext),
                                                              name: name, object: nil)
        }
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
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        mode = monitor == nil ? .off : next
        if model == nil && !loading {
            loading = true
            Task { [weak self] in
                let model = await Task.detached(priority: .utility) { PhraseModel.bundled }.value
                guard let self else { return }
                self.model = model
                self.loading = false
                if self.mode != .off && model == nil {
                    self.status = "Bundled language model unavailable"
                    self.changed()
                } else { self.inspect() }
            }
        }
        updateStatus()
    }

    private func receive(_ event: NSEvent) {
        if event.type == .scrollWheel { inline.hide(); return }
        let navigation = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home,
                          kVK_End, kVK_PageUp, kVK_PageDown, kVK_Tab, kVK_Escape, kVK_Delete, kVK_ForwardDelete]
        guard event.type == .keyDown, !IsSecureEventInputEnabled(),
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              !navigation.contains(Int(event.keyCode)) else { resetContext(); return }
        // AX focus notifications discard the binding; inspect and shortcut
        // actions also check it synchronously before accessing retained text.
        if owner == nil {
            guard let editor = Editor.current(), let caret = editor.selection, caret.length == 0,
                  observeFocus(editor) else { return }
            owner = editor
            // A global monitor may run just before or after the host inserts the key.
            // Include the current word only, never earlier completed sentences.
            let n = min(CompletedWord.maximumUTF16Length, caret.location)
            let suffix = editor.text(CFRange(location: caret.location - n, length: n)) ?? ""
            var fragment = suffix[...]
            if event.keyCode == kVK_Space || event.keyCode == kVK_Return, fragment.last?.isWhitespace == true {
                fragment = fragment.dropLast()
            }
            let word = fragment.reversed().prefix { !$0.isWhitespace }
            floor = caret.location - (suffix.utf16.count - fragment.utf16.count) - String(word.reversed()).utf16.count
        }
        if undo != nil { undo = nil; switchedLayout = false; updateStatus() }
        // Coalesce fast typing without postponing analysis indefinitely. The host
        // supplies committed text; a partially typed last word remains verbatim.
        let completedWord = [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode))
        guard boundary == nil, completedWord || pending != nil || session == nil else { return }
        boundary = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            guard !Task.isCancelled else { return }
            self.boundary = nil
            self.inspect()
        }
    }

    private func observeFocus(_ editor: Editor) -> Bool {
        var newObserver: AXObserver?
        guard AXObserverCreate(editor.pid, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<LiveCorrection>.fromOpaque(context).takeUnretainedValue().resetContext()
            }
        }, &newObserver) == .success, let newObserver else { return false }
        let app = AXUIElementCreateApplication(editor.pid)
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            guard AXObserverAddNotification(newObserver, app, name as CFString,
                    Unmanaged.passUnretained(self).toOpaque()) == .success else { return false }
        }
        observer = newObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        return true
    }

    @objc fileprivate func resetContext() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        owner = nil
        floor = 0
        clearEdits()
    }

    private func clearEdits() {
        inline.hide()
        boundary?.cancel()
        boundary = nil
        session = nil
        pending = nil
        undo = nil
        switchedLayout = false
        updateStatus()
    }

    private func updateStatus() {
        status = pending != nil ? (session?.full == true ? "Review accumulated corrections to continue" : "Layout suggestion available")
            : undo != nil ? "Layout corrected · Undo available"
            : mode == .off ? "Selected text only" : "\(mode.rawValue) · TextEdit and Notes"
        let state = "\(mode.rawValue)|\(status)|\(canUndo)"
        if state != menuState {
            menuState = state
            changed()
        }
    }

    private func inspect() {
        guard mode != .off, let owner, let model else { return }
        guard owner.focused else { resetContext(); return }
        if session == nil {
            guard let pair = try? SystemLayouts.pair() else { return }
            session = EditorPassage(editor: owner, start: floor, model: model, english: pair.english, russian: pair.russian)
        }
        guard let session, session.refresh() else { resetContext(); return }
        if mode == .automatic, let edit = session.edit(automatic: true) {
            guard edit.apply() else { resetContext(); return }
            switchedLayout = SystemLayouts.switchAfterCorrection(from: edit.language)
            undo = edit.reversed
            guard session.resumeAfterAutomaticEdit() else { resetContext(); return }
        }
        let hadPending = pending != nil
        pending = session.edit(automatic: false, accepting: true)
        if let pending, let preview = pending.preview, let caret = owner.selection, let bounds = owner.bounds(caret) {
            inline.show(preview, at: bounds) { [weak self] accept in
                guard let self else { return false }
                return accept ? self.accept() : self.dismiss()
            }
        } else {
            inline.hide()
        }
        if session.full && pending == nil { floor = session.end; self.session = nil }
        if pending != nil || hadPending || undo != nil { updateStatus() }
    }

    @discardableResult func dismiss() -> Bool {
        guard pending != nil, let session, session.refresh() else { resetContext(); return false }
        floor = session.end
        clearEdits()
        return true
    }

    @discardableResult func accept() -> Bool {
        guard pending != nil, let session, session.refresh(),
              let edit = session.edit(automatic: false, accepting: true), edit.apply() else { resetContext(); return false }
        floor = owner?.selection?.location ?? session.end
        clearEdits()
        undo = edit.reversed
        switchedLayout = SystemLayouts.switchAfterCorrection(from: edit.language)
        updateStatus()
        return true
    }

    func undoLast() {
        guard let undo, undo.apply() else { resetContext(); return }
        if switchedLayout { _ = SystemLayouts.switchAfterCorrection(from: undo.language) }
        floor = owner?.selection?.location ?? floor
        clearEdits()
    }
}
