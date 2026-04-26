#!/usr/bin/env python3
"""Extract Decision/Lesson trailers from the latest merged PR and append to memory/.

Convention (in PR body):

    Decision-Title: Short ADR title
    Decision-Context: What problem prompted this. May span multiple lines if needed.
    Decision-Rationale: Why this over alternatives. May span multiple lines.

    Lesson: build / one-line lesson body about build/tooling
    Lesson: gotchas / one-line lesson about a debugging trap
    Lesson: patterns / one-line lesson about an architectural pattern

Multiple `Lesson:` trailers allowed. One ADR per PR (Decision-Title is the
trigger; Context and Rationale are siblings of the same block).

Idempotency:
- DECISIONS entries carry an `<!-- pr:#N -->` marker. Re-running on the same PR
  is a no-op.
- LESSONS entries dedupe by exact body-match against existing bullets in the
  same section.

Tool-agnostic: invoked from the GitHub Action on push to main (where the
just-merged PR is the source) but also runnable locally with `--pr <num>` for
backfill or testing.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DECISIONS_PATH = REPO_ROOT / "memory" / "DECISIONS.md"
LESSONS_PATH = REPO_ROOT / "memory" / "LESSONS.md"

LESSON_SECTIONS = {
    "build": "## Build / Tooling",
    "tooling": "## Build / Tooling",
    "patterns": "## Patterns / Architecture",
    "architecture": "## Patterns / Architecture",
    "gotchas": "## Gotchas",
    "gotcha": "## Gotchas",
}


def gh_json(args: list[str]) -> dict | list:
    try:
        out = subprocess.check_output(["gh", *args], text=True, stderr=subprocess.PIPE)
        return json.loads(out) if out.strip() else {}
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip()
        print(f"gh call failed (exit {e.returncode}): {' '.join(['gh', *args])}", file=sys.stderr)
        if stderr:
            print(f"  stderr: {stderr}", file=sys.stderr)
        return {}


def pr_for_commit(sha: str) -> dict:
    """Find the PR that produced a given merge commit. Uses GitHub's
    /commits/{sha}/pulls endpoint, which returns PRs associated with the SHA."""
    data = gh_json(["api", f"/repos/{{owner}}/{{repo}}/commits/{sha}/pulls",
                    "--jq", "[.[] | {number, title, body, mergedAt, author}]"])
    return data[0] if data else {}


def latest_merged_pr() -> dict:
    """Fallback when no SHA is available (local dev). Returns globally most
    recent merged PR — not safe in CI under concurrent merges."""
    prs = gh_json(["pr", "list", "--state", "merged", "--limit", "1",
                   "--json", "number,title,body,mergedAt,author"])
    return prs[0] if prs else {}


def fetch_pr(num: int) -> dict:
    return gh_json(["pr", "view", str(num),
                    "--json", "number,title,body,mergedAt,author"])


def resolve_pr(args) -> dict:
    """Pick the PR to process. Priority:
    1. --pr <num>           (explicit, for backfill / local testing)
    2. $GITHUB_SHA          (CI: PR for the commit that triggered this run)
    3. latest merged PR     (local fallback)
    """
    if args.pr:
        return fetch_pr(args.pr)
    sha = os.environ.get("GITHUB_SHA", "").strip()
    if sha:
        pr = pr_for_commit(sha)
        if pr:
            return pr
        print(f"no PR found for commit {sha[:8]}, falling back to latest merged",
              file=sys.stderr)
    return latest_merged_pr()


def parse_trailers(body: str) -> tuple[dict | None, list[tuple[str, str]]]:
    """Return (decision_block, [(section, body), ...]).

    Decision block is the dict {title, context, rationale} or None.
    Lessons is a list of (section_key, lesson_body) tuples.
    """
    if not body:
        return None, []

    decision: dict[str, list[str]] = {}
    current_key: str | None = None
    lessons: list[tuple[str, str]] = []

    trailer_re = re.compile(r"^(Decision-Title|Decision-Context|Decision-Rationale|Lesson):\s*(.*)$")

    for raw in body.splitlines():
        line = raw.rstrip("\r")
        m = trailer_re.match(line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "Lesson":
                if "/" not in val:
                    print(f"warning: malformed Lesson trailer (missing /): {val!r}", file=sys.stderr)
                    current_key = None
                    continue
                section, body_part = val.split("/", 1)
                section = section.strip().lower()
                body_part = body_part.strip()
                if section in LESSON_SECTIONS and body_part:
                    lessons.append((section, body_part))
                else:
                    print(f"warning: unknown Lesson section {section!r}", file=sys.stderr)
                current_key = None
            else:
                slot = key.removeprefix("Decision-").lower()
                decision.setdefault(slot, [])
                decision[slot].append(val)
                current_key = slot
        elif current_key and line.strip() and not line.startswith(("Decision-", "Lesson:")):
            # Continuation of a Decision-* trailer (indented or wrapped lines)
            decision[current_key].append(line.strip())
        else:
            current_key = None

    decision_block = None
    if "title" in decision and decision["title"]:
        decision_block = {
            "title": " ".join(decision["title"]).strip(),
            "context": " ".join(decision.get("context", [])).strip(),
            "rationale": " ".join(decision.get("rationale", [])).strip(),
        }

    return decision_block, lessons


def append_decision(pr: dict, block: dict) -> bool:
    """Prepend a new ADR if not already present. Returns True if changed."""
    if not DECISIONS_PATH.exists():
        print(f"warning: {DECISIONS_PATH} missing, skipping decision append", file=sys.stderr)
        return False

    text = DECISIONS_PATH.read_text()
    pr_marker = f"<!-- pr:#{pr['number']} -->"
    if pr_marker in text:
        print(f"decision for PR #{pr['number']} already present, skipping")
        return False

    date = (pr.get("mergedAt") or "")[:10] or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    entry = (
        f"## [{date}] {block['title']} {pr_marker}\n"
        f"**Context:** {block['context']}\n"
        f"**Decision:** See PR #{pr['number']} for the implementation.\n"
        f"**Rationale:** {block['rationale']}\n"
    )

    # Insert after the closing `-->` of the template comment block, before the
    # first existing `## ` entry (or at end if none).
    lines = text.splitlines(keepends=True)
    insert_at = len(lines)
    saw_template_close = False
    for i, line in enumerate(lines):
        if "-->" in line and not saw_template_close:
            saw_template_close = True
            continue
        if saw_template_close and line.startswith("## "):
            insert_at = i
            break
        if saw_template_close and line.strip().startswith("_(no decisions"):
            # Replace the placeholder line itself
            lines[i] = ""
            insert_at = i
            break

    new_text = "".join(lines[:insert_at]) + entry + "\n" + "".join(lines[insert_at:])
    DECISIONS_PATH.write_text(new_text)
    print(f"appended decision: {block['title']!r} (PR #{pr['number']})")
    return True


def append_lessons(pr: dict, lessons: list[tuple[str, str]]) -> bool:
    """Append lesson bullets under their sections, dedup by exact body match."""
    if not LESSONS_PATH.exists():
        print(f"warning: {LESSONS_PATH} missing, skipping lessons append", file=sys.stderr)
        return False
    if not lessons:
        return False

    text = LESSONS_PATH.read_text()
    changed = False

    for section_key, body in lessons:
        header = LESSON_SECTIONS[section_key]
        if header not in text:
            print(f"warning: section {header!r} missing from LESSONS.md, skipping {body!r}",
                  file=sys.stderr)
            continue
        # Dedup: exact body substring already present anywhere in file means skip
        if body in text:
            print(f"lesson already present, skipping: {body!r}")
            continue

        # Find section header line, insert bullet right after the header
        # (before the next `## ` or EOF).
        bullet = f"- {body} _(PR #{pr['number']})_\n"
        lines = text.splitlines(keepends=True)
        for i, line in enumerate(lines):
            if line.rstrip() == header:
                # Skip past the placeholder italic if present
                j = i + 1
                while j < len(lines) and (lines[j].strip().startswith("_(") or lines[j].strip() == ""):
                    j += 1
                lines.insert(j, bullet)
                text = "".join(lines)
                changed = True
                print(f"appended lesson under {header}: {body!r}")
                break
        else:
            print(f"warning: section {header!r} not found, skipping", file=sys.stderr)

    if changed:
        LESSONS_PATH.write_text(text)
    return changed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--pr", type=int, help="PR number to extract from (default: latest merged)")
    args = ap.parse_args()

    pr = resolve_pr(args)
    if not pr or not pr.get("number"):
        print("no PR found to process", file=sys.stderr)
        return 0

    decision_block, lessons = parse_trailers(pr.get("body") or "")
    if not decision_block and not lessons:
        print(f"PR #{pr['number']}: no Decision/Lesson trailers found")
        return 0

    changed = False
    if decision_block:
        changed = append_decision(pr, decision_block) or changed
    if lessons:
        changed = append_lessons(pr, lessons) or changed

    if not changed:
        print(f"PR #{pr['number']}: nothing new to append")
    return 0


if __name__ == "__main__":
    sys.exit(main())
