import AppKit
import KeyOopsCore
import SelectionService

enum Failure: Error { case unexpected(String) }

@MainActor func scenario(_ name: String, input: String, secure: [Bool] = [false, false],
                         accept: Bool = true, change: Bool = false, preview: Bool,
                         expected: String, succeeds: Bool = false) throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    guard board.setString(input, forType: .string) else { throw Failure.unexpected("private pasteboard") }
    var checks = secure.makeIterator()
    var shown = false
    let service = CorrectionService(layouts: {
        let key = PhysicalKey(code: 0, shifted: false)
        return (KeyboardLayout(outputs: [key: "a"]), KeyboardLayout(outputs: [key: "ф"]))
    }, protectedInput: { checks.next() ?? true }, confirm: { _, _ in
        shown = true
        if change { board.clearContents(); board.setString("new selection", forType: .string) }
        return accept
    })
    let error = service.process(board)
    guard (error == nil) == succeeds, shown == preview, board.string(forType: .string) == expected
    else { throw Failure.unexpected(name) }
}

try scenario("accept", input: "a a", preview: true, expected: "ф ф", succeeds: true)
try scenario("reverse", input: "ф", preview: true, expected: "a", succeeds: true)
try scenario("cancel", input: "a", accept: false, preview: true, expected: "a")
try scenario("secure before read", input: "a", secure: [true], preview: false, expected: "a")
try scenario("secure after preview", input: "a", secure: [false, true], preview: true, expected: "a")
try scenario("changed selection", input: "a", change: true, preview: true, expected: "new selection")
try scenario("mixed scripts", input: "a ф", preview: false, expected: "a ф")
let oversized = String(repeating: "a", count: 4097)
try scenario("length bound", input: oversized, preview: false, expected: oversized)
print("Private Services pasteboard checks passed.")
