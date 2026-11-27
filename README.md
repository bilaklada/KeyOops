# KeyOops

KeyOops corrects English–Russian keyboard layout mistakes in selected text on macOS. If you meant to type **hello world** while Russian was active, select **руддщ цщкдв** and preview the correction. In the other direction, **ghbdtn vbh** becomes **привет мир**.

## Download the beta

[Get the universal macOS disk image](https://github.com/bilaklada/KeyOops/releases/tag/v0.2.1-beta.1) for macOS 14 or later. Open the DMG, drag KeyOops to Applications and launch it. The download runs on Intel and Apple silicon without a compiler. The beta uses an ad-hoc signature. See [first launch and beta limitations](docs/releases/0.2.1-beta.1.md).

## Build and use

1. On macOS 14 or later, install Xcode or Command Line Tools with Swift 6. Enable an English and a Russian keyboard layout in System Settings → Keyboard → Input Sources.
2. From the repository root, run `Scripts/build-app.sh`. Open `dist/KeyOops.app`. For ongoing use, move the app to Applications before launching it. The local build is ad-hoc signed.
3. In an editable field that supports macOS text Services, select the mistyped text. In the application's **Services** menu choose **Correct Keyboard Layout with KeyOops**.
4. Review the proposed text. Choose **Replace Selection** to apply it or **Cancel** to keep the original. Undo availability depends on the host editor.

A shortcut can be assigned under System Settings → Keyboard → Keyboard Shortcuts → Services. If the command is missing, check that the Service is enabled and the host has an editable plain-text selection.

## Scope and privacy

KeyOops reads enabled layouts at invocation time. The preferred layout is the active one when it matches the language. Otherwise there must be one enabled layout for that language. It handles ordinary and Shift-modified keys on the main typing block. Punctuation follows physical positions. Spaces, tabs and line breaks are preserved. Text alone cannot distinguish keypad input, Option combinations, Caps Lock or composed sequences from other ways of producing the same glyph.

The selection Service previews every replacement. Its label uses a small common-word vocabulary. Live mode additionally uses offline English and Russian dictionaries. Select only the affected span. Mixed scripts, ambiguous mappings, unsupported characters and selections over 4,096 characters are declined. The host controls whether it offers Services in a given field and how it inserts plain text, including formatting and undo.

## While typing

Choose **Suggest** or **Automatic** from the menu bar and grant Accessibility and Input Monitoring, then select the mode again. In a compatible focused text field, completing a word with whitespace checks both keyboard readings in context. Later words can resolve an earlier ambiguous spelling such as `руку` in an otherwise mistyped English sentence. Live mode starts Off at launch.

In **Suggest**, keep typing across sentences. **Tab** accepts the accumulated corrections and **Esc** dismisses them through the current caret. In supported code editors and spreadsheets, Option–Space accepts the suggestion and Tab keeps its usual behavior. The menu offers the same actions when the editor cannot position the preview. In **Automatic**, confident words and phrases are corrected at the next check. Wording with weaker evidence stays available for review. The menu offers undo for the latest applied edit until typing resumes.

KeyOops keeps one in-memory session of up to 4,096 UTF-16 units and scores a rolling window of up to 16 words. If a suggestion fills the session, it remains available while further typing stays outside that batch. Moving the caret, editing earlier text, or changing fields or apps ends the session. A compatible field must expose a writable selection, readable text ranges, and a verifiable document identity. Known terminals, password managers, system credential prompts, and secure fields are excluded. Browser and composer acceptance results are tracked in [live-host acceptance](docs/live-host-acceptance.md). After a successful live correction, KeyOops switches layouts if the source layout is still active. Undo attempts to restore it. The selection Service remains available in other apps and leaves the active layout alone. All processing is local. [Live-mode design](docs/decisions/002-live-correction.md)

## Engineering

The conversion rules, macOS layout reader and Services adapter are separate Swift targets. The [architecture decision](docs/decisions/001-selected-text.md) explains the interaction tradeoffs and reference project. See [development and verification](CONTRIBUTING.md), [changes](CHANGELOG.md), and [security reporting](SECURITY.md).

MIT licensed. Copyright © 2026 Lada Bilak. [License](LICENSE)
