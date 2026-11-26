# KeyOops

KeyOops corrects English–Russian keyboard layout mistakes in selected text on macOS. If you meant to type **hello world** while Russian was active, select **руддщ цщкдв** and preview the correction. In the other direction, **ghbdtn vbh** becomes **привет мир**.

## Download the beta

[Get the universal macOS disk image](https://github.com/bilaklada/KeyOops/releases/tag/v0.2.0-beta.3) for macOS 14 or later. Open the DMG, drag KeyOops to Applications and launch it. The download runs on Intel and Apple silicon without a compiler. The beta uses an ad-hoc signature. See [first launch and beta limitations](docs/releases/0.2.0-beta.3.md).

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

From the menu bar choose **Suggest** or **Automatic**, grant Accessibility and Input Monitoring to the installed app when prompted, then choose the mode again. While typing in TextEdit or Notes, Space checks the preceding word and up to three neighbors for a consistent layout mistake. A lone ambiguous key such as z stays as typed. In Suggest mode the menu bar indicates when a correction is available. Open the menu to see the proposed replacement, then accept or dismiss it. Automatic mode applies high-confidence candidates and offers undo in the menu. Continue typing, moving the caret or switching apps can invalidate a pending edit. Live mode starts Off on each launch.

Only these two editors are enabled for live checks. Compatibility varies by text control. The selection Service remains available in other apps that support macOS Services. After a successful live correction KeyOops switches to the target layout if the original layout is still active. Undo attempts to restore it. The selection Service leaves the layout alone.

All processing is local. The Service uses a transaction pasteboard. Live mode reads a bounded suffix from the focused text area and keeps at most one pending edit for 12 seconds. Neither mode keeps an input history, writes selection text to logs, or transmits text. [Live-mode design](docs/decisions/002-live-correction.md)

## Engineering

The conversion rules, macOS layout reader and Services adapter are separate Swift targets. The [architecture decision](docs/decisions/001-selected-text.md) explains the interaction tradeoffs and reference project. See [development and verification](CONTRIBUTING.md), [changes](CHANGELOG.md), and [security reporting](SECURITY.md).

MIT licensed. Copyright © 2026 Lada Bilak. [License](LICENSE)
