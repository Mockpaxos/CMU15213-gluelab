---
name: course-resources
description: Find course materials through resource mapping, clarification, broad search, and a candidate report.
---

# Vocabulary

- **Resource type:** Code-based assignments, slides, videos, or misc. Unclassified materials belong to misc.
- **Item:** One lab or project within code-based assignments.
- **Component:** A writeup, code, or required supporting files for an assignment; a lecture's slide deck for slides; or a recording for videos. Components can be bundled together or distributed separately.
- **Candidate:** A located copy of one or more components that may meet the request. Being a candidate does not establish usability.

# Workflow

## 1. Get the request

Prompt the user for a course URL, one resource type, a time range, and, for videos, a web-search tool choice. For misc, agree on search routes during grilling. Wait for their response. The goal is to find the newest relevant candidates within that scope.

## 2. Map the materials

Survey the course website and linked materials:
- **Code-based assignments:** Identify the items and known components. Keep items with unclear structure whole until more evidence reveals their components.
- **Slides and videos:** Identify collections and their expected coverage.
- **Misc:** Establish what the material appears to contain and what needs clarification.

Present a concise map with the course identity, observed structure or coverage, and unresolved details. This survey establishes search targets; the full search follows approval.

## 3. Clarify and obtain approval

Use the [grilling guide](../grilling.md) to clarify the request and resource map.

For misc, establish the meanings of item, component, and candidate as applicable, together with the evidence and limitations relevant to the request. Agree on GitHub and/or web-search routes and any web-search tool choice.

Summarize the agreed scope and wait for the user's approval to search.

## 4. Search and inspect

Use GitHub for code-based assignments and slides. For videos, use the chosen web-search tool and its supported query format. For misc, use the routes agreed during grilling. Consult command help as needed.

- Search broadly, using targeted queries to complement discovery. Apply hard exclusions only for agreed requirements; leave uncertain suitability to inspection.
- Follow leads beyond the initial URL, including instructor sites, repositories, mirrors, and linked files.
- Inspect promising candidates. Reject clear mismatches and retain plausible alternatives with their uncertainties.
- Record links, components present, offering evidence, relevant code state, and limitations while inspecting.
- Establish offering from the material's contents and course evidence, rather than repository creation or upload dates.

### GitHub search and result handling

Available avenues include repository and code search; forks and upstream repositories; file/tree inspection; branches, tags, and commit history; and commit search when author, hash, or message clues are useful. Use these as relevant, not as a mandatory checklist. Repository search excludes forks by default; use `fork:true` to include them or inspect a known repository's forks.

Use [scripts/github.py](scripts/github.py). It accepts a GitHub REST endpoint and repeated `--param KEY=VALUE` arguments, performs GET requests, saves complete JSON responses with request metadata, retrieves requested files, and prints status plus a readable result view. See `--help` for usage.

```bash
python3 <skill-dir>/scripts/github.py search/code --param 'q=YOUR QUERY' --param per_page=100
```

Reuse the same `--run-dir` throughout a search. Carefully decide whether to review more fetched records, fetch another page, refine the query, or stop. Do not create auxiliary narrative reports, coverage/audit summaries, or saved help files unless requested.

### Code-based assignments

Search each item and its components independently. Keep candidates from different offerings identifiable rather than attempting to assemble a compatible package.

Retain solution code as a candidate and continue seeking clean starter code. Report its observed state; restoration is outside this search.

When assignment or course evidence reveals additional required components, refine the map and search for missing parts without renewed approval. For example, a writeup may identify a support archive absent from the repository.

### Slides and videos

Search collection-first, then seek individual decks or recordings to fill identified gaps. Inspect offering, availability, and coverage against course evidence; mark unknown coverage as unknown.

### Misc

Apply the structure and criteria agreed during grilling.

### Completion

For unresolved components, pursue meaningfully different queries and sources. Continue while new leads produce useful alternatives. Finish when the agreed needs are covered or further approaches mainly repeat findings or fail to add useful alternatives, within any agreed effort budget.

Ask before expanding beyond the approved resource type or time range.

## 5. Report

Follow [references/reporting.md](references/reporting.md) and present the resulting report to the user.

## PDF tools

`pdfinfo`, `pdftotext`, `pdftoppm`, `tesseract` these tools may be useful, check availability when needed, then consult the tools' help for options. Keep downloads and extracts in the run's `cache/`.