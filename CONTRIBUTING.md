# Contributing

Thanks for your interest in Lumo. This is intentionally a small, simple app — please keep contributions aligned with that.

## Build

No Xcode required, just the Command Line Tools (Apple Silicon / macOS 13+).

```sh
swift build -c release   # build the binary
./make-app.sh            # produce dist/Lumo.app
open dist/Lumo.app       # the icon appears in the menu bar
```

You can also exercise behavior quickly in CLI mode.

```sh
.build/release/Lumo list      # list external displays
.build/release/Lumo get 1     # read brightness of display 1
```

## Code style

- When writing new code, **follow the conventions of the existing code** (indentation, naming, file layout).
- Don't bundle unrequested refactors or cleanup of adjacent code into a PR. One PR, one thing.
- Avoid adding dependencies. This project uses only the SwiftPM standard library plus IOKit/AppKit, no external packages.
- Anything that breaks the "no settings window, no background daemon" simplicity should be discussed in an issue first.

## PR workflow

1. Open an issue to share intent first (especially for features — let's agree on direction before you build).
2. Work on a small, focused branch.
3. Make sure `swift build -c release` passes without warnings and `./make-app.sh` builds the app cleanly.
4. If you can, note which monitor/setup you tested on in the PR description (DDC/CI behavior varies a lot across monitors).
5. Keep the PR title and description clear about what changed and why.

## Issue guide

For bug reports, please include:

- macOS version and Mac model (Apple Silicon chip)
- Monitor model and connection type (HDMI / DisplayPort / USB-C, etc.)
- Steps to reproduce, expected vs actual behavior
- For DDC issues, the output of `Lumo debug <n>` (the raw DDC reply dump)

For feature requests, explaining "why it's needed" and "how it keeps things simple" makes review faster.
