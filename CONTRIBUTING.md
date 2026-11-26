# Contributing

Build with Swift 6 on macOS. All commands run from the repository root.

| Command | What it verifies |
| --- | --- |
| `swift run VerifyCore` | Bidirectional physical-key mapping, punctuation, script and suggestion rules |
| `swift run VerifyLiveEdit` | Native AppKit text replacement, undo, moved caret, lost focus and failed host writes |
| `swift run VerifyService` | Acceptance, cancellation, size, secure input and stale private pasteboards |
| `swift run VerifyLayouts` | The enabled ABC and Russian layouts on a Mac configured with that pair |
| `Scripts/build-app.sh` | Release compilation, property list and ad-hoc signature |
| `Scripts/check-installed.swift` | Interactive round trip through the registered Service. Open the built app first and accept the synthetic preview. |

The verification executables run on a Command Line Tools installation without XCTest. Run the relevant checks for each change. For an interaction change, also try an editable plain-text selection in TextEdit, check cancellation and host Undo, and confirm that password fields decline Services. Record the tested host and macOS version in the pull request. Use synthetic text in bug reports.

Branch from main with a short purpose prefix such as feat/, fix/, test/ or docs/. Keep each Conventional Commit focused and describe the reason for non-obvious decisions in its body. Update the Unreleased section for user-visible changes. Tag releases using Semantic Versioning after verification.
