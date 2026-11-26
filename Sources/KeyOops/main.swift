import AppKit
import SelectionService

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
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
        let menu = NSMenu()
        menu.addItem(withTitle: "Ready · Select text and use Services", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KeyOops", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        item = status
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
