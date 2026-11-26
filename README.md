# KeyOops

KeyOops corrects English–Russian keyboard layout mistakes in selected text on macOS. If you meant to type **hello world** while Russian was active, select **руддщ цщкдв** and preview the correction. In the other direction, **ghbdtn vbh** becomes **привет мир**.

## Build and use

1. On macOS 14 or later, install Xcode or Command Line Tools with Swift 6. Enable an English and a Russian keyboard layout in System Settings → Keyboard → Input Sources.
2. From the repository root, run `Scripts/build-app.sh`. Open `dist/KeyOops.app`. For ongoing use, move the app to Applications before launching it. The local build is ad-hoc signed.
3. In an editable field that supports macOS text Services, select the mistyped text. In the application's **Services** menu choose **Correct Keyboard Layout with KeyOops**.
4. Review the proposed text. Choose **Replace Selection** to apply it or **Cancel** to keep the original. Undo availability depends on the host editor.

A shortcut can be assigned under System Settings → Keyboard → Keyboard Shortcuts → Services. If the command is missing, check that the Service is enabled and the host has an editable plain-text selection.

## Scope and privacy

KeyOops reads enabled layouts at invocation time. The preferred layout is the active one when it matches the language. Otherwise there must be one enabled layout for that language. It handles ordinary and Shift-modified keys on the main typing block. Punctuation follows physical positions. Spaces, tabs and line breaks are preserved. Text alone cannot distinguish keypad input, Option combinations, Caps Lock or composed sequences from other ways of producing the same glyph.

A small bundled vocabulary labels some candidates as likely mistakes. Every replacement requires confirmation. Select only the affected span. Mixed scripts, ambiguous mappings, unsupported characters and selections over 4,096 characters are declined. The host controls whether it offers Services in a given field and how it inserts plain text, including formatting and undo.

Processing takes place locally when the Service is invoked. KeyOops uses the Services transaction pasteboard, checks secure-input state, and requests zero Accessibility or Input Monitoring permissions. It keeps no input history and writes no selection text to logs. It has no analytics, network client, background typing monitor or global clipboard access.

## Engineering

The conversion rules, macOS layout reader and Services adapter are separate Swift targets. The [architecture decision](docs/decisions/001-selected-text.md) explains the interaction tradeoffs and reference project. See [development and verification](CONTRIBUTING.md), [changes](CHANGELOG.md), and [security reporting](SECURITY.md).

MIT licensed. Copyright © 2026 Lada Bilak. [License](LICENSE)
