import AppKit
import Carbon

/// A nonactivating panel leaves both keyboard focus and the insertion point in the host.
@MainActor final class InlineSuggestion {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
    private let label = NSTextField(wrappingLabelWithString: "")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var optionSpace = false
    fileprivate var handle: ((Bool) -> Bool)?

    init() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        panel.contentView = background
        background.addSubview(label)
    }

    var panelVisible: Bool { panel.isVisible }

    func hide() {
        panel.orderOut(nil)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        handle = nil
    }

    nonisolated static func shortcut(_ event: CGEvent, optionSpace: Bool = false) -> Bool? {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        guard event.type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
        let flags = event.flags.intersection(modifiers)
        if key == kVK_Escape && flags.isEmpty { return false }
        let accept = optionSpace ? (key == kVK_Space && flags == .maskAlternate) : (key == kVK_Tab && flags.isEmpty)
        return accept ? true : nil
    }

    func show(_ preview: String, at bounds: CGRect, optionSpace: Bool, handle: @escaping (Bool) -> Bool) {
        guard let primary = NSScreen.screens.first else { hide(); return }
        let anchor = CGPoint(x: bounds.minX, y: primary.frame.maxY - bounds.maxY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) else { hide(); return }
        self.optionSpace = optionSpace
        self.handle = handle
        if tap != nil {
            display(preview, anchor: anchor, caretHeight: bounds.height, screen: screen)
            return
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: inlineKeyCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        display(preview, anchor: anchor, caretHeight: bounds.height, screen: screen)
    }

    func display(_ preview: String, anchor: CGPoint, caretHeight: CGFloat, screen: NSScreen) {
        let excerpt = preview.count > 180 ? String(preview.prefix(85)) + " … " + String(preview.suffix(85)) : preview
        label.stringValue = excerpt + (optionSpace ? "    ⌥Space   ·   Esc" : "    ⇥ Tab   ·   Esc")
        let visible = screen.visibleFrame
        let width = min(visible.width - 20, min(460, ceil(label.attributedStringValue.size().width) + 8))
        guard let cell = label.cell else { hide(); return }
        let height = ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height)
        label.frame = NSRect(x: 10, y: 6, width: width, height: height)
        let size = NSSize(width: width + 20, height: height + 12)
        let below = anchor.y - size.height - 3
        let y = below >= visible.minY ? below : anchor.y + caretHeight + 3
        panel.setFrame(NSRect(x: max(visible.minX, min(anchor.x, visible.maxX - size.width)),
                              y: min(y, visible.maxY - size.height), width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

private func inlineKeyCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                               _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    // This tap is installed exclusively on the main run loop.
    let owner = Unmanaged<InlineSuggestion>.fromOpaque(context).takeUnretainedValue()
    let optionSpace = MainActor.assumeIsolated { owner.optionSpace }
    let shortcut = InlineSuggestion.shortcut(event, optionSpace: optionSpace)
    let consumed = MainActor.assumeIsolated {
        guard type == .keyDown, owner.panelVisible, let shortcut else {
            if type != .keyDown { owner.hide() }
            return false
        }
        return owner.handle?(shortcut) == true
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
