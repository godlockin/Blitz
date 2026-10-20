# Blitz vs other clipboard / launcher tools (2026)

Survey of Mac clipboard-strengthening apps and launcher-bundled history, then where **Blitz** sits. Sources: vendor sites + 2026 roundups ([Maccy](https://maccy.app/), [Paste](https://pasteapp.io/), [Clipy](https://github.com/Clipy/Clipy), [Raycast clipboard](https://manual.raycast.com/clipboard-history), CmdSpace / TypeFire / QuietClip comparisons).

---

## Landscape (horizontal)

Two product shapes:

| Shape | Examples | Job |
|---|---|---|
| **Clipboard specialist** | Maccy, Clipy, Paste, Flycut, CopyQ, CopyClip, CleanClip, ClipBook | History + paste (+ sync / polish) |
| **Launcher + clipboard** | Raycast, Alfred Powerpack, Blitz | Root search + history as one workflow |

Blitz deliberately sits in the **second** row (Raycast-like daily driver) while borrowing **Clipy-depth** clipboard menus — not a Maccy clone.

---

## Feature matrix

| Capability | Blitz | Maccy | Clipy | Paste | Raycast (free) | Alfred Powerpack | CopyQ |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Price | Free OSS | Free OSS | Free OSS | Sub / lifetime | Free (+ Pro) | Paid license | Free OSS |
| Open source | Yes | Yes | Yes | No | No | No | Yes |
| Clipboard search | Yes (panel) | Yes | Weak / menu | Yes | Yes | Yes | Yes |
| Images in history | Yes | Yes (basic) | Limited | Strong | Yes | Yes | Yes |
| OCR / text in images | Yes (on-device) | No | Internal only (1.4) | Yes | Yes (Pro-ish actions) | No | No |
| Pin / favorites | Yes | Yes | No | Pinboards | Yes | Limited | Tags |
| Snippets | Yes (folders + hotkeys) | No | Yes | Shelves | Yes | Yes | Scripts |
| Exclude apps / concealed | Yes | Password-aware | Yes | Yes | Yes | Yes | Rules |
| Menu-bar Clipy-style menus | Yes | Overlay list | Yes | Board UI | Raycast UI | Alfred UI | Qt UI |
| App / file launcher | Yes | No | No | No | Yes | Yes | No |
| Calculator in search | Yes | No | No | No | Yes | Yes | No |
| Window snap | Yes | No | No | No | Yes | Workflows | No |
| Quicklinks / local scripts | Yes | No | No | No | Yes | Workflows | CLI/scripts |
| iCloud / multi-device sync | No | No | No | Yes | Limited UC | No | No |
| Public notarized DMG | No (self-sign / ad-hoc CI) | Yes (MAS/Homebrew) | Yes (Developer ID) | Yes | Yes | Yes | Varies |
| AI / MCP | No (out of scope) | No | No | Paste MCP | Pro AI | No | No |

---

## Vertical slices

### 1. Pure clipboard (Blitz vs Maccy / Clipy / Paste)

| | Strength | Gap vs Blitz |
|---|---|---|
| **Maccy** | Fastest “one job” OSS; tiny; great search; Homebrew | No snippets, no launcher, weak rich types vs Blitz; no OCR |
| **Clipy** | Classic menu + snippets; tiny | Little search; slower maintenance; Blitz aims at Clipy **parity+** (types, pin, OCR, SQLite) **plus** launcher |
| **Paste** | Best polish + iCloud + pinboards | Paid, closed; Blitz wins on OSS + launcher, loses on sync/UI polish |

**Verdict:** For clipboard-only users, Maccy remains the default OSS pick. Blitz is competitive when you also want **snippets + menus like Clipy** and **image OCR**, but packaging trust (notarization) still lags Maccy/Clipy releases.

### 2. Launcher-bundled clipboard (Blitz vs Raycast / Alfred)

| | Strength | Gap vs Blitz |
|---|---|---|
| **Raycast** | Polished clipboard + huge ecosystem; free history (time-capped) | Closed; Pro for long retention / AI; Blitz is clean-room OSS subset (no extensions marketplace) |
| **Alfred** | Workflow depth; clipboard tied to Powerpack | Paid; Blitz free but far fewer workflows |

**Verdict:** Blitz’s bet is **OSS Raycast-shaped daily driver without AI/cloud** — clipboard depth closer to Clipy than to Maccy’s minimalism. Gaps vs Raycast: extensions, polish, notarized install, retention UX, ecosystem.

### 3. Power / cross-platform (CopyQ)

CopyQ wins on scripting, tabs, encryption options, Linux/Windows. Loses native macOS feel. Blitz stays Mac-native AppKit and does not try to match CopyQ’s script surface.

---

## Where Blitz is ahead (today)

- **Combo:** launcher + Clipy-class clipboard + snippets + window snap + quicklinks/scripts in one MIT agent app  
- **Clipboard types:** text / image / RTF / HTML / PDF / files / URL / color + screenshot ingest + OCR  
- **Pin** that survives clear/trim  
- **Local-only** by design (no sync telemetry story)

## Where Blitz is behind

| Gap | Who is better | Notes |
|---|---|---|
| Install trust | Clipy, Maccy, Paste, Raycast | Need Developer ID + notarization for one-click Open |
| Cross-device sync | Paste | Out of scope while unpaid / local-first |
| Clipboard-only speed/polish | Maccy, Paste | Overlay UX; Blitz panel is functional |
| Extension / workflow ecosystem | Raycast, Alfred | Explicitly out of v1 |
| Cross-platform | CopyQ | macOS only |
| Ship cadence / brand recognition | All of the above | Early OSS |

---

## Positioning one-liner

> **Blitz = open-source local launcher + Clipy-plus clipboard**, not a Paste sync client and not a Raycast Pro substitute. Closest OSS peers: **Maccy** (clipboard purity) and **Clipy** (menus/snippets); closest product *shape*: **Raycast free** without AI/extensions.

---

## Sources (checked ~2026)

- https://maccy.app/ · https://github.com/p0deje/Maccy  
- https://github.com/Clipy/Clipy  
- https://pasteapp.io/  
- https://manual.raycast.com/clipboard-history  
- https://cmd-space.app/blog/mac-clipboard-history-options  
- https://typefire.app/blog/best-clipboard-manager-mac  
- https://quietclip.app/blog/clipboard-manager-comparison/
