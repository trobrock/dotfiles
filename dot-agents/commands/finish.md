---
name: finish
description: Validate, independently review, fix, and re-review the current work
argument-hint: "[focused|include-qa|review-only|branch]"
---
Load the `finish-work` skill and follow it to finish the current work.

Apply these optional mode arguments: $ARGUMENTS

Use the current conversation to recover the intended behavior and acceptance criteria. Review all relevant work, load applicable project-specific guidance, validate with appropriate checks, request an independent read-only subagent review using the `reviewer` role, verify its findings, make the smallest coherent fixes unless in review-only mode, and perform a bounded re-review when changes warrant it. When manual or browser QA applies, delegate it to a subagent using the `qa` role. Do not commit, push, open or merge a pull request, deploy, or mutate production unless separately requested.
