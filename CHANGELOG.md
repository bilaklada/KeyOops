# Changelog

## Unreleased

### Fixed

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
