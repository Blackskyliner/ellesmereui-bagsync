#!/usr/bin/env python3
"""Turns the fragments in changelog.d/ into the CHANGELOG.md section of a version.

    scripts/changelog-release.py <version>

The release pull request runs it: it writes "## <version>" above the newest
section with every waiting entry, sorted New, Enhanced, Bugfix, Removed and
within a prefix by the time its fragment was added (git), sets the version in
the TOC and in the README's "Version x, by" line, and deletes the fragments.
scripts/release-check.sh <version> checks the result.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PREFIXES = ["New", "Enhanced", "Bugfix", "Removed"]
ENTRY = re.compile(r"^- \*\*(%s):\*\* \S" % "|".join(PREFIXES))


def added_at(path):
    """Unix time of the commit that added the fragment; untracked ones sort last."""
    out = subprocess.run(
        ["git", "-C", str(ROOT), "log", "--diff-filter=A", "--format=%ct", "-1", "--", str(path)],
        capture_output=True, text=True, check=False,
    ).stdout.strip()
    return int(out) if out else float("inf")


def entries(path):
    """The entries of a fragment, each with its continuation lines."""
    result = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        if ENTRY.match(line):
            result.append([line])
        elif line.startswith("  ") and result:
            result[-1].append(line)
        else:
            sys.exit(f"{path.relative_to(ROOT)}: not an entry or its continuation: {line}")
    if not result:
        sys.exit(f"{path.relative_to(ROOT)}: no entry")
    return ["\n".join(lines) for lines in result]


def set_line(path, pattern, replacement):
    text = path.read_text(encoding="utf-8")
    new, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
    if count != 1:
        sys.exit(f"{path.relative_to(ROOT)}: no line matches {pattern}")
    path.write_text(new, encoding="utf-8")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: changelog-release.py <version>")
    version = sys.argv[1]
    fragments = sorted(p for p in (ROOT / "changelog.d").glob("*.md") if p.name != "README.md")
    if not fragments:
        sys.exit("changelog.d holds no fragments")

    collected = []
    for path in fragments:
        when = added_at(path)
        for index, text in enumerate(entries(path)):
            prefix = ENTRY.match(text).group(1)
            collected.append((PREFIXES.index(prefix), when, path.name, index, text))
    collected.sort()

    changelog = ROOT / "CHANGELOG.md"
    text = changelog.read_text(encoding="utf-8")
    if re.search(r"^## %s$" % re.escape(version), text, flags=re.M):
        sys.exit(f"CHANGELOG.md already has a ## {version} section")
    section = f"## {version}\n\n" + "\n".join(e[-1] for e in collected) + "\n\n"
    first = re.search(r"^## ", text, flags=re.M)
    text = text[: first.start()] + section + text[first.start():] if first else text.rstrip("\n") + "\n\n" + section
    changelog.write_text(text, encoding="utf-8")

    set_line(ROOT / "EllesmereUIBags_Alts" / "EllesmereUIBags_Alts.toc", r"^## Version: .*$", f"## Version: {version}")
    set_line(ROOT / "README.md", r"^Version \S+, by", f"Version {version}, by")
    for path in fragments:
        path.unlink()
    print(f"CHANGELOG.md: ## {version} with {len(collected)} entries from {len(fragments)} fragments; TOC and README set")


if __name__ == "__main__":
    main()
