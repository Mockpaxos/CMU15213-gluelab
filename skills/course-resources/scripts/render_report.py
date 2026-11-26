#!/usr/bin/env python3
"""Render the course-resources report framework from JSON, without rewriting content."""
import argparse
import json
import re
from pathlib import Path

COLUMNS = ("link", "components", "evidence", "limitations")


def fields(value, required, optional=()):
    if not isinstance(value, dict):
        raise ValueError("Expected an object")
    missing = set(required) - value.keys()
    extra = value.keys() - set(required) - set(optional)
    if missing or extra:
        raise ValueError(f"Missing fields: {sorted(missing)}; unknown fields: {sorted(extra)}")


def string(value):
    if not isinstance(value, str):
        raise ValueError("Report text fields must be strings")
    return value.replace("\r\n", "\n").replace("\r", "\n").strip()


def cell(value):
    # Preserve existing escapes; escape unescaped table separators, including in code spans.
    text = re.sub(r"(\\*)\|", lambda m: m[1] + ("\\" if len(m[1]) % 2 == 0 else "") + "|", string(value))
    return text.replace("\n", "<br>")


def render(report):
    fields(report, ("scope", "groups"))
    if not isinstance(report["groups"], list) or not report["groups"]:
        raise ValueError("groups must be a nonempty list")
    lines = [f"**Scope:** {string(report['scope'])}", ""]
    for group in report["groups"]:
        fields(group, ("title", "status", "candidates"), ("important_distinctions",))
        if not isinstance(group["candidates"], list):
            raise ValueError("candidates must be a list (it may be empty)")
        distinctions = group.get("important_distinctions", [])
        if not isinstance(distinctions, list):
            raise ValueError("important_distinctions must be a list")
        title = string(group["title"]).replace("\n", " ")
        lines.extend([f"## {title}", "", f"**Status:** {string(group['status'])}", "",
                      "| Candidate link | Components | Evidence | Limitations |",
                      "|---|---|---|---|"])
        for candidate in group["candidates"]:
            fields(candidate, COLUMNS)
            lines.append("| " + " | ".join(cell(candidate[key]) for key in COLUMNS) + " |")
        if distinctions:
            lines.extend(["", "### Important distinctions", ""])
            for item in distinctions:
                lines.append("- " + string(item).replace("\n", "\n  "))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Filled report JSON")
    parser.add_argument("--output", type=Path, help="Also save the Markdown, normally RUN/findings.md")
    args = parser.parse_args(argv)
    try:
        markdown = render(json.loads(args.input.read_text(encoding="utf-8")))
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(markdown, encoding="utf-8")
    except (ValueError, OSError) as exc:
        parser.exit(1, f"Report error: {exc}\n")
    print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
