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
        item?.button?.title = live.canAccept ? "KeyOops · Suggestion" : "KeyOops"
        menu.addItem(withTitle: live.status, action: nil, keyEquivalent: "")
        for mode in LiveCorrection.Mode.allCases {
            let row = menu.addItem(withTitle: mode.rawValue, action: #selector(changeMode(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = mode.rawValue
            row.state = live.mode == mode ? .on : .off
        }
        if live.canAccept {
            menu.addItem(withTitle: "Accept layout suggestion", action: #selector(accept), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Dismiss", action: #selector(dismiss), keyEquivalent: "").target = self
        }
        if live.canUndo {
            menu.addItem(withTitle: "Undo layout correction", action: #selector(undo), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KeyOops", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let row = menu.items.first(where: { $0.action == #selector(accept) }) else { return }
        if let candidate = live.suggestionPreview {
            row.title = "Accept “" + candidate + "”"
        } else {
            row.title = "Suggestion expired"
            row.action = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(accept) })?.title = "Accept layout suggestion"
    }

    @objc private func accept() { live.accept() }
    @objc private func dismiss() { live.dismiss() }
    @objc private func undo() { live.undoLast() }
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
