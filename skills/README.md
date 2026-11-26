# Course skills

| Skill | Purpose | Tools |
| --- | --- | --- |
| [course-resources](course-resources/SKILL.md) | Find course materials and report candidates, evidence, and gaps in `findings.md`. | Python 3 for the helpers; web access to inspect course pages; authenticated GitHub CLI (`gh`) for GitHub searches. Video searches need a web-search tool. |
| [course-assembler](course-assembler/SKILL.md) | Use `findings.md` to propose lab components, then copy the approved files into a local Git repository. | Bash, Git configured to make commits, and standard Unix utilities (`find`, `mkdir`). |

For PDF inspection, `course-resources` can optionally use Poppler (`pdfinfo`, `pdftotext`, `pdftoppm`) and Tesseract OCR (`tesseract`).

The [grilling guide](grilling.md) used by `course-resources` is from [Matt Pocock’s grilling skill](https://github.com/mattpocock/skills/blob/main/skills%2Fproductivity%2Fgrilling%2FSKILL.md).
