# Pull request

## What changed

One or two lines: the user-visible or byte-visible difference this branch makes.

## Why

The problem this solves, or the evidence that makes it a real defect. Link the issue if there is one.

## Evidence

Paste the terminal output from **this branch**, not from memory or from `main`. A successful build says nothing about save-level results, so keep the three commands separate.

```
$ dart format .
# paste the summary line, or write "no changes"

$ flutter analyze
# paste the final line; it must be: No issues found!

$ flutter test
# paste the final line, in the form +<passed> ~<skipped> -<failed>
```

Flutter / Dart version (`flutter --version`):

```
<paste here>
```

## Checklist

- [ ] Analyzer is clean and the pasted output is from this branch.
- [ ] Test output pasted; no test I touched is skipped and I added no new `skip:`.
- [ ] No assertion was weakened, deleted, loosened, or given a wider tolerance to make the suite pass.
- [ ] Round-trip preserved: unedited bytes re-encode identically (or, for a save-format change, the changed byte span is exactly the declared field span).
- [ ] Any new format offset/default is cited to evidence and verified against the game or the samples; unverified fields stay read-only.
- [ ] No `flutter/`, `flutter_bloc/`, `bloc/`, `material_ui/`, `bitsdojo_window/` in domain/data; domain also no `equatable/`, `dart:io`, `dart:ui`; presentation no `dart:io` (cubits: ARCHITECTURE)
- [ ] No save, ROM, dump, `.local-fixtures/` content, or other game data is in the diff.
- [ ] Screenshots or a short capture attached for any UI change (empty state and populated state if the tab renders save data).
- [ ] Commits are path-scoped, one concern each, Conventional Commits with a scope; history is not force-pushed or rebased.
- [ ] `docs/` updated only where the change makes a documented claim false (link the doc you touched, or say "none").

## Notes for reviewers

Generated `linux/flutter/` registrant files (`generated_plugin_registrant.*`, `generated_plugins.cmake`) are produced by the Flutter tool. Do not hand-edit them in review; re-run `flutter pub get` or a build instead.
