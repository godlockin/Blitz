# Blitz GitHub Actions

These workflows assume **this folder is the git root** (standalone Blitz repo).

| File | Trigger |
|---|---|
| `workflows/ci.yml` | push / PR |
| `workflows/release.yml` | tag `v*` |

When Blitz lives inside the **Reverse** monorepo, GitHub runs the adapters at the monorepo root:

- `.github/workflows/blitz-ci.yml` — only on `blitz/**` changes  
- `.github/workflows/blitz-release.yml` — tag `blitz-v*`

Do not rely on this nested `.github/` to run while still under Reverse; GitHub ignores nested workflow directories.
