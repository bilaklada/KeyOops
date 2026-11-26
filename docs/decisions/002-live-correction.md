# 002 · Live correction in supported editors

A selection-only Service leaves a layout mistake in place until the writer invokes it. The live modes add one decision point when the writer finishes a word with Space. They start off on every launch.

The global event monitor checks the key code and shortcut modifiers. It does not decode the typed characters. For an ordinary space in a supported app, Accessibility supplies at most 51 UTF-16 units before a collapsed caret. KeyOops requires a writable text area and excludes secure input. The initial live host list is TextEdit and Notes. Replacing selected text through Accessibility avoids synthesizing delete or paste events. Focus, range and original text are checked again before a change. A pending suggestion or inverse edit expires after 12 seconds and is cleared on app switch, session resign or sleep.

The detector preserves recognized source words. It can suggest a known target word of at least three letters. Automatic mode requires a frequent target of at least four letters and ordinary capitalization. Unknown names can still resemble layout mistakes. Suggest mode leaves acceptance to the writer. Mixed-script tokens, commands containing punctuation and unsupported editors receive no live edit. Keyboard source switching and correction inside terminals are outside this milestone.
