#!/usr/bin/env python3
"""Check that every image target in README.md and docs/**/*.md resolves.

Scans markdown image syntax ``![alt](target)`` and HTML ``<img src="target">``.
A target is resolved relative to the file that references it. Absolute and
remote targets (``http(s)://``, ``data:``, and anything starting with ``/``)
are reported with a distinct ``REMOTE``/``ABSOLUTE`` status and never fetched.

Exit codes: 0 = all local targets exist, 1 = at least one ``MISSING``,
2 = self-test failure.

Usage:
    python3 docs/check_image_paths.py [--root REPO] [--self-test]
    python3 docs/check_image_paths.py --self-test
"""

from __future__ import annotations

import argparse
import io
import re
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

MD_IMAGE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML_IMG = re.compile(r"<img\b[^>]*?\bsrc=\"([^\"]+)\"", re.IGNORECASE)
REMOTE_PREFIXES = ("http://", "https://", "data:")


def extract(paths: list[Path]) -> list[tuple[Path, int, str]]:
    found: list[tuple[Path, int, str]] = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for pattern in (MD_IMAGE, HTML_IMG):
            for match in pattern.finditer(text):
                line = text[: match.start()].count("\n") + 1
                found.append((path, line, match.group(1)))
    return found


def targets(root: Path) -> list[Path]:
    files = [root / "README.md"] if (root / "README.md").is_file() else []
    docs = root / "docs"
    if docs.is_dir():
        files.extend(sorted(docs.rglob("*.md")))
    return files


def report(root: Path) -> tuple[str, int]:
    files = targets(root)
    found = extract(files)
    lines = [
        f"files scanned: {len(files)}",
        f"image targets found: {len(found)}",
    ]
    missing = 0
    for source, line, target in found:
        shown = source.relative_to(root) if source.is_relative_to(root) else source
        if target.startswith(REMOTE_PREFIXES):
            lines.append(f"{shown}:{line}: {target} -> REMOTE (not checked)")
            continue
        if target.startswith("/"):
            lines.append(f"{shown}:{line}: {target} -> ABSOLUTE (not checked)")
            continue
        resolved = (source.parent / target).resolve()
        ok = resolved.exists()
        missing += 0 if ok else 1
        lines.append(f"{shown}:{line}: {target} -> {'OK' if ok else 'MISSING'} ({resolved})")
    return "\n".join(lines), (1 if missing else 0)


def self_test() -> int:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        (root / "docs" / "images").mkdir(parents=True)
        (root / "docs" / "images" / "present.png").write_bytes(b"\x89PNG\r\n\x1a\n")
        (root / "README.md").write_text(
            "# Title\n\n"
            '<img src="docs/images/present.png" alt="ok" width="200">\n\n'
            "![missing](docs/images/absent.png)\n\n"
            "![remote](https://example.com/x.png)\n"
            "![absolute](/var/tmp/local-only.png)\n",
            encoding="utf-8",
        )
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            text, code = report(root)
        print(text)
        checks = [
            ("present.png reported OK", "present.png -> OK" in text),
            ("absent.png reported MISSING", "absent.png -> MISSING" in text),
            ("remote target skipped", "-> REMOTE (not checked)" in text),
            ("absolute target skipped", "-> ABSOLUTE (not checked)" in text),
            ("one missing target yields exit 1", code == 1),
        ]
        for label, ok in checks:
            print(f"self-test {'PASS' if ok else 'FAIL'}: {label}")
        return 0 if all(ok for _, ok in checks) else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    text, code = report(args.root.resolve())
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
