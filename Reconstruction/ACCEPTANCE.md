# Blitz — Acceptance

## Hard rules

- Bundle id: `research.reversedir.blitz`
- Name / URL scheme: Blitz / `blitz://`
- No Raycast binaries, assets, or license bypass
- Distribution stays **local Blitz Dev** self-sign (no paid Developer ID / notarization)

## MVP daily-driver gate (must all pass)

1. Launch at login optional; runs as agent (no Dock icon by default)
2. Configurable global hotkey opens AppKit search panel
3. Typing filters installed apps; Enter launches
4. Clipboard history lists recent items; Enter pastes; pin survives Clear
5. Snippet keyword expansion works (Accessibility)
6. Window snap (halves / center) works (Accessibility)
7. Quicklinks / scripts appear in launcher search and have an editor
8. `make install` → `~/Applications/Blitz.app` signed as **Blitz Dev**

## Status

Track milestones in `STATUS.json`. Broader Raycast-map extras are `parity-core-later` in `OBLIGATIONS.json`, not MVP blockers.
