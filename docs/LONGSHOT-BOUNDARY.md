# Longshot boundary

Longshot (`/home/daze/GitHub/Longshot`) is a separate project and is
**strictly read-only** for Bomb Flower work.

## Allowed

- Reading Longshot's `docs/` for terminology, save-layout notes, and naming.
- Using Longshot save data or fixtures only if they are supplied as test
  fixtures inside **this** repository and contain no copyrighted game assets.

## Not allowed

- Writing, editing, formatting, building, or running tests in Longshot.
- Any `git` mutation in Longshot (commit, branch, tag, remote, stash, etc.).
- Copying ROMs, ripped assets, artwork, audio, or proprietary data from
  Longshot or anywhere else into this repository.
- Making Bomb Flower's build or tests depend on a checked-out Longshot path.

## Why

Bomb Flower is an independent save editor and save creator. Treating Longshot
as a read-only reference keeps both projects independently buildable and keeps
the boundary between "documentation input" and "runtime dependency" explicit.

Any future shared format specification must be copied into this repo as
original prose (or linked), never imported from Longshot at build time.
