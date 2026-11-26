# Candidate report

Group code-based assignments by item. For slides and videos, show collections first and individual gap-filling candidates afterward. For misc, use the grouping agreed during grilling.

If no run directory exists yet, create one with a `cache/` subdirectory.

Fill this framework in `<run>/cache/report.json`:

```json
{
  "scope": "<Approved course, resource type, and time range>",
  "groups": [
    {
      "title": "<Item or collection>",
      "status": "<Requested materials found; unresolved components or coverage; alternatives retained>",
      "candidates": [
        {
          "link": "[<label>](<URL>)",
          "components": "<What is provided>",
          "evidence": "<Offering first, then its basis>",
          "limitations": "<Relevant gaps or uncertainty>"
        }
      ],
      "important_distinctions": ["<Decision-relevant distinction across candidates>"]
    }
  ]
}
```

Repeat groups and candidates as needed.

Run the renderer and present that as the report:

```bash
python3 <skill-dir>/scripts/render_report.py <run>/cache/report.json --output <run>/findings.md
```

## Column guidance

- **Candidate link:** Link directly to useful material where possible. Aggregate related components from one repository, archive, or collection when that stays clear. Split rows when aggregation would hide different editions or important limitations.
- **Components:** State what is present. For assignments, identify writeup, code, and required support files; mark code as starter, solution, mixed, or uninspected. For slides and videos, describe the decks or recordings covered. Use the agreed structure for misc.
- **Evidence:** Start with the offering when known, then briefly state what identifies the course, edition, or contents. For example: “SP26 — PDF header,” or “Offering unknown — repository claims 2026; included files are undated.” Distinguish a hosting page's description from observations inside the material. Do not assign a repository-wide edition to mixed contents.
- **Limitations:** State decision-relevant gaps, access problems, and uncertainty. Distinguish **not inspected** (unchecked), **not found** (not located in the search or inspected material), and **unavailable** (an access problem was observed). For assignments, note missing required files or unclear code state; for slides/videos, note missing lectures or unknown expected coverage. For misc, use the concerns agreed during grilling.

Keep cells concise. Show meaningful alternatives rather than every redundant mirror.
