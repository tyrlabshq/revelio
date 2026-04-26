#!/usr/bin/env python3
"""Archive SESSION_LOG.md entries older than RETENTION_DAYS.

Entries start with `## [YYYY-MM-DD ...]` headers. Entries older than the cutoff
are moved to `memory/archive/SESSION_LOG_YYYY-MM.md` (one archive file per
calendar month, append-only). Newer entries stay in `memory/SESSION_LOG.md`.

Idempotent: re-running with no eligible entries makes no writes.

Tool-agnostic: invoked from a GitHub Action on push to main, or run locally
(`python3 scripts/archive-session-log.py`).
"""

import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SESSION_LOG = REPO_ROOT / "memory" / "SESSION_LOG.md"
ARCHIVE_DIR = REPO_ROOT / "memory" / "archive"
RETENTION_DAYS = int(os.environ.get("ARCHIVE_RETENTION_DAYS", "30"))

# Matches `## [YYYY-MM-DD]` or `## [YYYY-MM-DD HH:MM]` at the start of a line.
ENTRY_HEADER = re.compile(r"^## \[(\d{4}-\d{2}-\d{2})(?:[^\]]*)\]", re.MULTILINE)


def split_entries(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Split text into (preamble, [(date_str, full_entry_text), ...]).

    Preamble is everything before the first `## [YYYY-MM-DD]` header.
    Each entry includes its header line plus body up to the next header.
    """
    matches = list(ENTRY_HEADER.finditer(text))
    if not matches:
        return text, []

    preamble = text[: matches[0].start()]
    entries = []
    for i, m in enumerate(matches):
        date_str = m.group(1)
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        entries.append((date_str, text[start:end]))
    return preamble, entries


def main() -> int:
    if not SESSION_LOG.exists():
        print(f"no SESSION_LOG.md at {SESSION_LOG} — nothing to archive")
        return 0

    text = SESSION_LOG.read_text()
    preamble, entries = split_entries(text)

    if not entries:
        print("SESSION_LOG.md has no dated entries — nothing to archive")
        return 0

    today = datetime.now(timezone.utc).date()
    cutoff = today - timedelta(days=RETENTION_DAYS)

    keep: list[tuple[str, str]] = []
    archive_by_month: dict[str, list[str]] = {}

    for date_str, body in entries:
        try:
            entry_date = datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            print(f"warning: unparseable date '{date_str}' — keeping in main log", file=sys.stderr)
            keep.append((date_str, body))
            continue

        if entry_date >= cutoff:
            keep.append((date_str, body))
        else:
            month_key = entry_date.strftime("%Y-%m")
            archive_by_month.setdefault(month_key, []).append(body)

    if not archive_by_month:
        print(f"all {len(entries)} entries within retention ({RETENTION_DAYS}d) — nothing to archive")
        return 0

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

    archived_count = 0
    for month_key, bodies in sorted(archive_by_month.items()):
        archive_path = ARCHIVE_DIR / f"SESSION_LOG_{month_key}.md"
        existing = archive_path.read_text() if archive_path.exists() else f"# Session Log Archive — {month_key}\n\n"
        # Append entries; ensure single blank line between entries.
        new_block = "\n".join(b.rstrip() for b in bodies) + "\n"
        archive_path.write_text(existing.rstrip() + "\n\n" + new_block)
        archived_count += len(bodies)
        print(f"archived {len(bodies)} entries to {archive_path.relative_to(REPO_ROOT)}")

    # Rewrite SESSION_LOG.md with preamble + kept entries.
    new_log = preamble.rstrip() + "\n\n" if preamble.strip() else ""
    new_log += "".join(body for _, body in keep)
    SESSION_LOG.write_text(new_log)

    print(f"SESSION_LOG.md trimmed: {archived_count} archived, {len(keep)} retained")
    return 0


if __name__ == "__main__":
    sys.exit(main())
