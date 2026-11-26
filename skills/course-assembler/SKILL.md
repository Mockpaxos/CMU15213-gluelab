---
name: course-assembler
description: Discuss course lab candidates provided in findings, then assemble the user's approved components into a local Git repository.
---

# Vocabulary

- **Component:** Starter code, a writeup, tests, a driver, or other supporting files for a course lab or project. Components may be bundled or distributed separately.
- **Candidate:** A located copy of one or more components.

# Workflow

## 1. Discuss

The user provides findings and questions in their prompts. Wait for their questions and answer them; enter the proposal phase only when the user explicitly requests it.

Accept the path to `findings.md` anywhere in the user's request. Resolve relative paths from the current working directory. If the path is missing or ambiguous, ask which file to use. Its parent directory is the **search folder**. Reuse its `cache/` for downloads, extracts, and working files without overwriting existing search artifacts.

## 2. Proposal

Ask for the destination path if the user has not provided one. Use that exact directory.

Follow the component selections agreed during discussion. Otherwise, propose the newest clean candidate for each component, using the offering evidence rather than upload dates. Use the supplied candidates. Surface unresolved choices instead of silently substituting components or manufacturing a starter from a solution.

Show the resolved destination and a concrete Markdown table with exactly these columns:

| Source candidate | Components |
|---|---|
| [Offering — candidate](SOURCE_URL) | Specific files or component groups to copy from this candidate |

Link to the useful source, identify its course offering, and make each selection unambiguous.

Wait for explicit approval of the destination, table, and any local adaptations. If the selection or adaptations change, present the revised proposal for approval. Do not create the lab or save `assemble.md` before approval. If `assemble.md` already exists, obtain approval to replace it as well.

## 3. Assemble

After approval, save the approved table as `<search-folder>/assemble.md`, beside `findings.md`.

Prepare the destination by running [scripts/prepare_repo.sh](scripts/prepare_repo.sh) from the current working directory, passing the approved path as one argument. Resolve `<skill-dir>` to this skill's directory:

```bash
bash "<skill-dir>/scripts/prepare_repo.sh" "/approved/destination"
```

Create commits in this order:

1. **Initial commit:** Copy only the approved lab components, preserving their original contents. Stage and commit these files before making any local adaptations.
2. **Second commit (only if local adaptations are approved):** Apply the approved changes and illustrate what are changed in the commit message.

Component compatibility checks are not needed. If assembly cannot proceed as agreed, report the blocker rather than improvising changes.
