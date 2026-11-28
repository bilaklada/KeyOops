# Changelog

## Unreleased

- Copy an entire corrected passage from the menu. Identifiable fields without readable ranges can now show contextual suggestions from uninterrupted typing.

- Show preview-only suggestions in recognized source editors and readable, verified typing fields that cannot replace a selection.

- Discover editable combo boxes, explicitly editable groups and focused text leaves across apps. Bind embedded editors to their web document even when it omits a URL. Skip recognized source editor controls.

- Extend live mode to compatible single-line and multiline controls with document-scoped ownership. Preserve Tab in editors and spreadsheets. Real-host verification is tracked in [live-host acceptance](docs/live-host-acceptance.md).

- Suggest mode collects contextual corrections across sentences until Tab or Esc. Automatic mode applies confident phrase readings and revisits ambiguous words as more text arrives. Live sessions are bounded and tied to one focused editor.

## 0.2.0-beta.3

- Use adjacent words as evidence for English–Russian corrections. Recover short pronouns and prepositions in context and keep ambiguous single keys unchanged.
- Show the proposed wording when opening the live suggestion menu. Honor a dismissal or undo when looking back from the next word.

## 0.2.0-beta.2

### Fixed

- Recognize Russian words mapped to English punctuation keys in suggestions.

- Live corrections verify the host actually changed the text before switching layouts. Rejected writes preserve a newer user selection. Continued typing dismisses stale suggestions and undo.

## 0.2.0-beta.1

First packaged preview for macOS 14 and later.

### Added

- Preview and correct selected English or Russian text using the host application's Services menu.
- Resolve physical-key mappings from enabled macOS layouts, including shifted keys.
- Label likely mistakes using a small local English and Russian vocabulary.
- Decline mixed-script selections, ambiguous physical-key readings and secure-input transactions.

- Opt-in live suggestions and automatic correction in supported TextEdit and Notes text areas, with guarded layout switching and short-lived undo.
- English and Russian offline Hunspell-derived lexicons with upstream acknowledgments.
- Universal drag-to-install disk image with a SHA-256 checksum and native Intel and Apple silicon CI.
