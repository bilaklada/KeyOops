# 001 · Correct an explicit selection

## Context

Text often has two plausible readings. The English word “he” occupies the same keys as Russian “ру”. Names, commands and mixed-language messages make dictionary-only decisions particularly fragile.

## Decision

Start with a native macOS Service. The user selects the scope and requests correction. The host supplies the selection on a service pasteboard and handles replacement. A preview lets the user cancel. A keyboard shortcut can invoke the Service through System Settings. This approach costs an extra gesture and depends on the host's Services support.

Continuously suggested correction could reduce selection effort, but would require observing typing and dismissing incorrect prompts. Automatic correction saves the most gestures, but an incorrect edit can silently change a valid name, word or command. Both require evidence from representative typing and protected-field testing before adoption.

Separate conversion from intent detection. Use enabled English and Russian Unicode keyboard layouts and the hardware keyboard type. Reconstruct ordinary and shifted physical keys. Selection text has lost the original key events. Decline ambiguous mappings and mixed-script selections. Leave unrelated scripts and unsupported layouts outside the supported scope.

## Provenance

Tilqos informed the investigation of Text Input Services and physical-key conversion. Its code is MIT licensed, and its language resources carry separate terms. KeyOops uses an independent implementation and ships no Tilqos assets. [Tilqos](https://github.com/elapen/tilqos)
