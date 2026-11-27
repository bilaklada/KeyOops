import Foundation

/// Some editors expose the same URL in multiple tabs. Compare the complete
/// ancestry, including each actual web document element and its current URL.
package struct EditorIdentity<Element: Equatable>: Equatable {
    package struct Document: Equatable {
        package let area: Element
        package let url: URL
        package init(area: Element, url: URL) { self.area = area; self.url = url }
    }

    let pid: pid_t
    let window: Element
    let field: Element
    let document: String?
    let ancestry: [Document]

    package init(pid: pid_t, window: Element, field: Element, document: String?, ancestry: [Document]) {
        self.pid = pid
        self.window = window
        self.field = field
        self.document = document
        self.ancestry = ancestry
    }
}
