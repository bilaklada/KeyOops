# KeyOops

KeyOops is a macOS utility in development for English–Russian keyboard layout mistakes. For example, `ghbdtn` and `привет` occupy the same keys on ABC and Russian. Conversion depends on the keyboard layout and modifier state.

## Development

The first milestone is a deterministic conversion library. The macOS adapter will read enabled keyboard layouts so punctuation follows the user's actual input sources. See [the design decision](docs/decisions/001-selected-text.md) for interaction and privacy constraints.
