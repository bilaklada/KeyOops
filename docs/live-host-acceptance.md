# Live-host acceptance

Release status: cross-application live editing is pending real-host acceptance on macOS 26.5.1. The installed KeyOops was left in place. A successful DOM test proves that the fixture is correctly prepared; it does not exercise the macOS Accessibility bridge.

| Host | Control | Fixture result | KeyOops live correction, isolation, undo and preview latency |
| --- | --- | --- | --- |
| Safari | Single-line input | WebDriver session refused because Remote Automation is off | Pending |
| Safari | Textarea | Same WebDriver restriction | Pending |
| Safari | Rich-text composer | Same WebDriver restriction | Pending |
| Chrome 158.0.8127.89 | Single-line input | Identical text and caret verified in two isolated pages | Pending |
| Chrome 158.0.8127.89 | Textarea | Identical text and caret verified in two isolated pages | Pending |
| Chrome 158.0.8127.89 | Rich-text composer | Identical text and caret verified in two isolated pages | Pending |
| Firefox Nightly 150.0.2 | Single-line input | Identical text and caret verified in two isolated pages | Pending |
| Firefox Nightly 150.0.2 | Textarea | Identical text and caret verified in two isolated pages | Pending |
| Firefox Nightly 150.0.2 | Rich-text composer | Identical text and caret verified in two isolated pages | Pending |
| Apple Mail | Unsent compose body | Pending | Pending |
| VS Code (Electron) | Unsent chat composer | Pending | Pending |

The real-host verifier exited with status 77 at macOS permission preflight. The fixture checks used headless Chrome and Firefox. The release AppKit harness measured 710 µs p95 for refreshing and validating a near-capacity preview. Warm decoder p95 was 64 µs. The bilingual corpus had zero false automatic edits in 2,224 valid three-word windows. These measurements exclude cross-process AX calls and panel presentation.

## Run the host checks

1. Build the candidate with `Scripts/build-app.sh` and run just that copy of KeyOops. Grant Accessibility and Input Monitoring to the candidate and grant Accessibility to the process that runs the host verifier. Keep KeyOops Off for the verifier's direct transaction checks.
2. Open `Tests/HostFixtures/editor.html` in the host. Use the URL fragments `#single`, `#multi` and `#rich` to focus each type of editor. Each starts with the same three-sentence sample and an end caret. For Mail and an Electron chat composer, use the same sample, including the final space, in an empty unsent draft.
3. Run `swift run -c release VerifyHost roundtrip com.google.Chrome` and focus the prepared control. Substitute the frontmost host bundle identifier for the other apps. The verifier uses the production identity and notification checks, requires an exact fixture match, checks both suggestion and automatic projections, applies and reverses each edit, and reports AX refresh/preview/bounds p95. A timeout or an unsupported AX operation is a failed compatibility check. Capture the host, version, control, outcome and timing.
4. Run `swift run -c release VerifyHost isolation com.google.Chrome`. After it captures the first fixture, switch to an identical second field with the same caret. Repeat between duplicate tabs with the same URL, between windows, and on navigation in one tab. The stale edit must be refused and the second fixture remain intact.
5. Check the actual live UI in each control. Clear the disposable field, enable Suggest, type the two reported passages and a third sentence, then press Tab. Check the full replacement and menu Undo. Repeat with Esc and continue typing. In Automatic, continue typing after the keyboard switches and verify the final text and the latest Undo. Check ordinary Tab when the preview is absent or stale. Check Option–Space in the Electron editor and a spreadsheet. Enter a password control and a terminal with a pending suggestion and confirm that the preview closes and no text changes.
6. For actual event-to-preview timing, trace the candidate's `LivePreview` signposts in Instruments while typing in each host. Measure `Live update` intervals containing a `Preview visible` event. Report p95 per host alongside the direct AX timing. The interval includes event coalescing and panel update, and the markers contain no text or URL.

Use a fresh fixture for each repetition. Opening the file normally in Safari does not require Safari Remote Automation; that setting is specific to WebDriver.
