import AppKit
import SelectionService

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private let live = LiveCorrection()
    private let service = CorrectionService { candidate, likely in
        let alert = NSAlert()
        alert.messageText = likely ? "Likely layout mistake" : "Review layout correction"
        alert.informativeText = candidate
        alert.addButton(withTitle: "Replace Selection")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = service
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "KeyOops"
        item = status
        live.changed = { [weak self] in self?.refresh() }
        refresh()
    }

    private func refresh() {
        let menu = NSMenu()
        menu.delegate = self
        item?.button?.title = live.hasSuggestion ? "KeyOops · Suggestion" : "KeyOops"
        menu.addItem(withTitle: live.status, action: nil, keyEquivalent: "")
        for mode in LiveCorrection.Mode.allCases {
            let row = menu.addItem(withTitle: mode.rawValue, action: #selector(changeMode(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = mode.rawValue
            row.state = live.mode == mode ? .on : .off
        }
        func addAction(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = live.actionGeneration
        }
        if live.hasSuggestion { addAction("Copy corrected passage", #selector(copyPassage)) }
        if live.hasSuggestion && !live.canAccept {
            let row = menu.addItem(withTitle: "Preview", action: nil, keyEquivalent: "")
            row.identifier = NSUserInterfaceItemIdentifier("preview")
            addAction("Dismiss", #selector(dismiss))
        }
        if live.canAccept {
            addAction("Accept layout suggestion", #selector(accept))
            addAction("Dismiss", #selector(dismiss))
        }
        if live.canUndo {
            addAction("Undo layout correction", #selector(undo))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KeyOops", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let preview = menu.items.first(where: { $0.identifier?.rawValue == "preview" }) {
            preview.title = live.suggestionPreview.map { "Suggestion: " + $0 } ?? "Suggestion expired"
        }
        guard let row = menu.items.first(where: { $0.action == #selector(accept) }) else { return }
        if let candidate = live.suggestionPreview {
            row.title = "Accept “" + candidate + "”"
        } else {
            row.title = "Suggestion expired"
            row.action = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menu.items.first(where: { $0.identifier?.rawValue == "preview" })?.title = "Preview"
        menu.items.first(where: { $0.action == #selector(accept) })?.title = "Accept layout suggestion"
    }

    @objc private func copyPassage(_ sender: NSMenuItem) {
        if sender.representedObject as? UUID == live.actionGeneration { live.copySuggestion() }
    }

    @objc private func accept(_ sender: NSMenuItem) {
        if sender.representedObject as? UUID == live.actionGeneration { live.accept() }
    }
    @objc private func dismiss(_ sender: NSMenuItem) {
        if sender.representedObject as? UUID == live.actionGeneration { live.dismiss() }
    }
    @objc private func undo(_ sender: NSMenuItem) {
        if sender.representedObject as? UUID == live.actionGeneration { live.undoLast() }
    }
    @objc private func changeMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let mode = LiveCorrection.Mode(rawValue: value) else { return }
        live.set(mode, prompt: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
