import AppKit
import Carbon

/// A nonactivating panel leaves both keyboard focus and the insertion point in the host.
@MainActor final class InlineSuggestion {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
    private let label = NSTextField(wrappingLabelWithString: "")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
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

    func hide() {
        panel.orderOut(nil)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        handle = nil
    }

    nonisolated static func shortcut(_ event: CGEvent) -> Bool? {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        guard event.type == .keyDown, event.flags.intersection(modifiers).isEmpty,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              key == kVK_Tab || key == kVK_Escape else { return nil }
        return key == kVK_Tab
    }

    func show(_ preview: String, at bounds: CGRect, handle: @escaping (Bool) -> Bool) {
        hide()
        guard let primary = NSScreen.screens.first else { return }
        let anchor = CGPoint(x: bounds.minX, y: primary.frame.maxY - bounds.maxY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) else { return }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: inlineKeyCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.handle = handle
        display(preview, anchor: anchor, caretHeight: bounds.height, screen: screen)
    }

    func display(_ preview: String, anchor: CGPoint, caretHeight: CGFloat, screen: NSScreen) {
        label.stringValue = preview + "    ⇥ Tab   ·   Esc"
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
    let shortcut = type == .keyDown ? InlineSuggestion.shortcut(event) : nil
    let consumed = MainActor.assumeIsolated {
        defer { owner.hide() }
        guard let shortcut else { return false }
        return owner.handle?(shortcut) == true
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
