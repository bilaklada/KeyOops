import AppKit
import ApplicationServices
import Carbon

/// macOS text offsets are UTF-16 units. Keep the exact inspected range for the
/// reply so an edit, focus change or selection change invalidates it.
@MainActor package struct FocusedEditor: LiveTextEditor {
    private let focusTarget: AXUIElement
    private let identity: EditorIdentity<AXUIElement>
    private var element: AXUIElement { identity.field }
    package var pid: pid_t { identity.pid }
    private let documentMarker: CFTypeRef?
    private final class Lifetime { var valid = true }
    private let lifetime = Lifetime()

    package func invalidate() { lifetime.valid = false }

    package func sameTarget(as other: Self) -> Bool { identity == other.identity && CFEqual(focusTarget, other.focusTarget) }

    package let bundle: String
    package private(set) var canReplace = false
    private let restrictedEditor: Bool
    package let optionSpace: Bool
    private var documents: [EditorIdentity<AXUIElement>.Document] { identity.ancestry }

    package static func current(checkCapabilities: Bool = true,
                                onUnavailable: (String) -> Void = { _ in }) -> Self? {
        func unavailable(_ reason: String) -> Self? {
            onUnavailable(reason)
            return nil
        }
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
              LiveHostPolicy.enabled(bundle) else { return unavailable("Protected or excluded context") }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var target = node(application, kAXFocusedUIElementAttribute)
        if checkCapabilities, target.map({ candidate in
            LiveHostPolicy.textControl(role: attribute(candidate, kAXRoleAttribute) as? String ?? "",
                                       editable: attribute(candidate, "AXEditable") as? Bool)
        }) != true {
            // Chromium and Electron can start with a minimal Accessibility tree.
            // Only request modes the host advertises, then query focus again.
            for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
                var supported = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(application, name as CFString, &supported) == .success,
                      supported.boolValue, attribute(application, name) as? Bool != true else { continue }
                if AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanTrue) == .success {
                    target = node(application, kAXFocusedUIElementAttribute)
                    break
                }
            }
        }
        guard let target,
              let window = node(application, kAXFocusedWindowAttribute) else { return unavailable("No focused text control") }
        // Walk to the focused window, including the innermost web document for
        // iframe editors. A URL alone identifies neither a tab nor a document.
        var current = target
        var editingControl: AXUIElement?
        var canResolveControl = true
        var documents = [EditorIdentity<AXUIElement>.Document]()
        var optionSpace = LiveHostPolicy.usesOptionSpace(bundle)
        var restrictedEditor = false
        var reachedWindow = false
        // One IPC per ancestor. Deep web trees otherwise multiply the cost
        // of each focus check by the number of security/identity attributes.
        let names = [kAXRoleAttribute, kAXSubroleAttribute, "AXDOMClassList", "AXProtectedContent",
                     kAXParentAttribute, kAXURLAttribute, kAXEnabledAttribute, "AXEditable", "AXReadOnly"]
        for _ in 0..<64 {
            var raw: CFArray?
            let batch = AXUIElementCopyMultipleAttributeValues(current, names as CFArray, [], &raw)
            let values: [AnyObject]
            if batch == .success, let items = raw as? [AnyObject], items.count == names.count,
               items.allSatisfy(Self.availableOrUnsupported) {
                values = items
            } else {
                // Some accessibility bridges implement individual reads but
                // cannot return all metadata through the batch operation.
                guard batch == .success || batch == .notImplemented || batch == .attributeUnsupported ||
                      batch == .illegalArgument else { return unavailable("Field metadata unavailable (\(batch.rawValue))") }
                var items = [AnyObject]()
                for (index, name) in names.enumerated() {
                    if batch == .success, let cached = raw as? [AnyObject], cached.count == names.count,
                       Self.availableOrUnsupported(cached[index]) {
                        items.append(cached[index])
                        continue
                    }
                    var value: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(current, name as CFString, &value)
                    if result == .success, let value {
                        items.append(value)
                    } else if result == .attributeUnsupported || result == .noValue {
                        items.append(NSNull())
                    } else {
                        return unavailable("Cannot verify \(name) (\(result.rawValue))")
                    }
                }
                values = items
            }
            guard let ancestorRole = values[0] as? String else { return unavailable("Missing accessibility role") }
            guard (values[3] as? NSNumber)?.boolValue != true else { return unavailable("Host marks content protected") }
            guard !LiveHostPolicy.excludesControl(subrole: values[1] as? String, classes: []) else {
                return unavailable("Excluded secure or system control")
            }
            guard !LiveHostPolicy.excludesControl(subrole: nil, classes: values[2] as? [String] ?? []) else {
                return unavailable("Inside a terminal")
            }
            // Resolve a focused text leaf to its nearest editing container. Stop
            // at unrelated controls and document boundaries, while checking
            // even the leaf and its ancestors for protected content.
            if editingControl == nil {
                guard canResolveControl, (values[6] as? NSNumber)?.boolValue != false,
                      (values[7] as? NSNumber)?.boolValue != false,
                      (values[8] as? NSNumber)?.boolValue != true else { return unavailable("Read-only or unsupported control") }
                if LiveHostPolicy.textControl(role: ancestorRole, editable: values[7] as? Bool) {
                    editingControl = current
                } else {
                    canResolveControl = ["AXStaticText", "AXGroup", "AXLayoutArea"].contains(ancestorRole)
                }
            }
            restrictedEditor = restrictedEditor || LiveHostPolicy.previewOnly(subrole: values[1] as? String, classes: values[2] as? [String] ?? [])
            optionSpace = optionSpace || LiveHostPolicy.reservesTab(role: ancestorRole, classes: values[2] as? [String] ?? [])
            if ancestorRole == "AXWebArea" {
                let url = values[5] as? URL ?? (values[5] as? String).flatMap(URL.init(string:))
                // Embedded documents may omit their URL. Their live element
                // and mandatory navigation/destruction observers still bind them.
                documents.append(.init(area: current, url: url))
            }
            if CFEqual(current, window) { reachedWindow = true; break }
            guard CFGetTypeID(values[4]) == AXUIElementGetTypeID() else { return unavailable("Incomplete field ancestry") }
            let parent = values[4] as! AXUIElement
            guard !CFEqual(parent, current) else { return unavailable("Invalid field ancestry") }
            current = parent
        }
        guard let field = editingControl, reachedWindow, !LiveHostPolicy.requiresWebDocument(bundle) || !documents.isEmpty else { return unavailable("Cannot identify the field and document") }
        let fieldDocument = attribute(field, kAXDocumentAttribute) as? String
        let document = fieldDocument ?? (bundle == "com.apple.Notes" ? nil : attribute(window, kAXDocumentAttribute) as? String)
        var documentMarker: CFTypeRef?
        // TextEdit creates a distinct document window even before the first save.
        if documents.isEmpty && document?.isEmpty != false && bundle != "com.apple.TextEdit" {
            guard AXUIElementCopyParameterizedAttributeValue(field, "AXTextMarkerForIndex" as CFString,
                    0 as CFNumber, &documentMarker) == .success, documentMarker != nil else { return unavailable("Host lacks document identity") }
        }
        let identity = EditorIdentity(pid: app.processIdentifier, window: window, field: field,
                                      document: document, ancestry: documents)
        var editor = Self(focusTarget: target, identity: identity, documentMarker: documentMarker, bundle: bundle, restrictedEditor: restrictedEditor, optionSpace: optionSpace)
        if checkCapabilities {
            editor.canReplace = !restrictedEditor && [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute].allSatisfy { name in
                var writable = DarwinBoolean(false)
                return AXUIElementIsAttributeSettable(field, name as CFString, &writable) == .success && writable.boolValue
            }
            guard let count = editor.characterCount, let caret = editor.selection,
                  caret.length == 0, caret.location <= count else { return unavailable("Host lacks a readable insertion point") }
            let probe = CFRange(location: max(0, caret.location - 1), length: caret.location == 0 ? 0 : 1)
            guard editor.text(probe)?.utf16.count == probe.length else { return unavailable("Host cannot read a bounded text range") }
        }
        return editor
    }

    private static func availableOrUnsupported(_ value: AnyObject) -> Bool {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return true }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .axError else { return true }
        var error = AXError.failure
        return AXValueGetValue(ax, .axError, &error) && (error == .attributeUnsupported || error == .noValue)
    }

    static func node(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = attribute(element, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    package var characterCount: Int? { (Self.attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue }

    package var selection: CFRange? {
        guard let raw = Self.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    func rangeValue(_ range: CFRange) -> AXValue? {
        var copy = range
        return AXValueCreate(.cfRange, &copy)
    }

    package func text(_ range: CFRange) -> String? {
        guard let value = rangeValue(range) else { return nil }
        var text: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element,
                kAXStringForRangeParameterizedAttribute as CFString, value, &text)
        if result == .success { return text as? String }
        guard result == .attributeUnsupported || result == .parameterizedAttributeUnsupported,
              AXUIElementCopyParameterizedAttributeValue(element,
                kAXAttributedStringForRangeParameterizedAttribute as CFString, value, &text) == .success
        else { return nil }
        return (text as? NSAttributedString)?.string
    }

    package func bounds(_ range: CFRange) -> CGRect? {
        guard let value = rangeValue(range) else { return nil }
        var raw: CFTypeRef?
        var rect = CGRect.zero
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                  value, &raw) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID(),
              AXValueGetValue(raw as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return rect
    }

    package func select(_ range: CFRange) -> Bool {
        guard canReplace, focused, let value = rangeValue(range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    package func replaceSelection(with text: String) -> Bool {
        canReplace && focused && AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Attach the same lifetime notifications in the app and the real-host verifier.
    package func registerInvalidation(on observer: AXObserver, context: UnsafeMutableRawPointer) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            guard AXObserverAddNotification(observer, app, name as CFString, context) == .success else { return false }
        }
        for document in documents {
            for name in ["AXLoadComplete", kAXUIElementDestroyedNotification] {
                guard AXObserverAddNotification(observer, document.area, name as CFString, context) == .success else { return false }
            }
        }
        return true
    }

    package var focused: Bool {
        guard lifetime.valid, let current = Self.current(checkCapabilities: false),
              sameTarget(as: current), restrictedEditor == current.restrictedEditor, optionSpace == current.optionSpace else { invalidate(); return false }
        guard let documentMarker else { return true }
        var index: CFTypeRef?
        let valid = AXUIElementCopyParameterizedAttributeValue(current.element, "AXIndexForTextMarker" as CFString,
            documentMarker, &index) == .success && ((index as? NSNumber)?.intValue ?? -1) >= 0
        if !valid { invalidate() }
        return valid
    }
}
