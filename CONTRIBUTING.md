# Contributing to Blitz

## Principles

1. **Clean-room** — no Raycast binaries, assets, trademarks, or copied proprietary code. Raycast notes live under the parent Reverse repo’s `research/raycast/` and are reference-only.
2. **Permission-safe installs** — sign with local **Blitz Dev** (`make signing-cert`) so Accessibility survives rebuilds.
3. **No paid Apple account required** — do not add notarization / Developer ID as a hard dependency for everyday builds.
4. **Small PRs** — one feature or fix when possible.

## Develop

```bash
make signing-cert   # once per machine
make install        # ~/Applications/Blitz.app
```

Logs: `~/Library/Logs/Blitz.log`  
Data: `~/Library/Application Support/Blitz/`

## Releases

Tag `v*` → `.github/workflows/release.yml` (ad-hoc zip).  
Prefer `make install` locally for stable Accessibility (**Blitz Dev**).

## Scope

| In | Out (for now) |
|---|---|
| Launcher, clipboard, snippets, files, calc, window snap | AI / cloud sync |
| Clipy-parity clipboard depth | Notarized public DMG (needs paid Developer ID) |
| Local scripts & quicklinks | Full extension marketplace |

## License

MIT — see [LICENSE](./LICENSE).
