#!/usr/bin/env swift
import AppKit

// Interactive smoke test. Uses the registered app and never touches the clipboard.
@MainActor func verify() -> Bool {
    NSApplication.shared.finishLaunching()
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    guard board.setString("руддщ цщкдв", forType: .string) else { return false }
    guard NSPerformService("Correct Keyboard Layout with KeyOops", board) else {
        print("macOS reported that the Service did not complete.")
        return false
    }
    guard board.string(forType: .string) == "hello world" else {
        print("The Service completed but the returned selection did not match.")
        return false
    }
    print("Registered Service returned the expected correction.")
    return true
}
exit(MainActor.assumeIsolated { verify() } ? EXIT_SUCCESS : EXIT_FAILURE)
