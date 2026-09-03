---
name: finish-work
description: Finish implementation work with project-aware validation, an independent subagent review for correctness and simplicity, verified fixes, and a bounded re-review loop
---

# Finish Work

Use this skill when the user asks to finish, final-review, QA, polish, or get implementation work ready to ship. It orchestrates the final quality pass; it does not replace project-specific coding, design, testing, or QA guidance.

## Goal

Leave the requested work in a demonstrably sound state by:

1. understanding the complete change and its intended behavior;
2. applying the repository's own standards;
3. validating behavior with appropriate checks;
4. obtaining an independent, read-only review;
5. verifying and fixing material findings; and
6. reporting evidence and remaining uncertainty clearly.

Do not commit, push, open a pull request, merge, deploy, or mutate production unless the user separately requested that action.

## Interpret Arguments

Treat optional user arguments as refinements:

- `focused`: prefer changed-file tests and checks; skip broad suites unless risk warrants them.
- `include-qa`: perform applicable manual or browser QA in addition to automated checks.
- `review-only`: report findings without modifying files.
- `branch`: review the complete branch diff from its merge base, including working-tree changes.

When no mode is supplied, review the complete work relevant to the current task. In Git repositories this normally includes both committed branch changes since the default branch's merge base and uncommitted changes. Use the conversation and repository evidence to avoid pulling unrelated pre-existing changes into scope.

## 1. Establish Scope and Baseline

Before reviewing:

1. Read the repository instructions and identify applicable project skills and canonical documentation.
2. Inspect repository status, the relevant diff, and recent commit history.
3. Determine the comparison base when reviewing committed branch work. Do not assume `main` if repository evidence identifies another default branch.
4. Restate the intended behavior and important invariants from the user's request.
5. Identify risk areas suggested by the change, such as authorization, tenancy, money, persistence, migrations, concurrency, retries, external APIs, security, accessibility, or responsive UI.
6. Note unrelated user changes and preserve them.

Load project-specific skills before judging their domain. Examples include clean-code, design-system, components, financial transactions, localization, background jobs, and browser QA skills.

If the work or intended behavior is genuinely ambiguous and the ambiguity blocks correctness, ask the user rather than inventing requirements.

## 2. Run Baseline Validation

Choose checks from repository instructions and changed-file evidence rather than using a fixed global command list.

- Run focused tests covering changed behavior first.
- Run relevant linters, type checks, formatting checks, migration checks, or build checks.
- Use broader tests when the change is cross-cutting or the focused checks cannot establish confidence.
- Perform manual or browser QA when explicitly requested, when required by project instructions, or when automated checks cannot reasonably validate user-facing behavior.
- For plans, documentation, configuration, or other non-code artifacts, use the corresponding structural validation instead of forcing code checks.

Record exact commands and outcomes. A pre-existing or unrelated failure must be identified as such only when evidence supports that conclusion.

## 3. Request an Independent Review

Use one focused, read-only subagent by default. Add parallel reviewers only when the diff is broad enough to contain genuinely independent domains, such as financial correctness and UI behavior. More reviewers are not inherently better.

Give the reviewer enough context to work independently:

- the user's intended behavior and acceptance criteria;
- the review scope and comparison base;
- repository instructions and applicable project skill paths;
- the relevant diff and nearby implementation or test paths;
- baseline validation results; and
- known constraints or deliberate tradeoffs.

Ask the reviewer to inspect, not edit. The review must prioritize:

1. behavioral correctness and conformity to the request;
2. regressions, edge cases, invalid states, error handling, and data integrity;
3. security, authorization, tenancy, concurrency, and financial risks when applicable;
4. missing or weak behavior-focused tests;
5. conformity with repository instructions and relevant project skills; and
6. opportunities to remove accidental complexity without speculative refactoring.

Require each finding to include:

- severity;
- file and location;
- the concrete failure mode or maintenance cost;
- supporting evidence or a reproduction path; and
- the smallest reasonable correction.

Tell the reviewer to omit preferences unsupported by project guidance or nearby conventions and to return `CLEAN` when there are no material findings.

Do not hard-code a provider or model. Use the configured subagent/explore model unless the user requested a particular provider or model. If a requested model is unavailable, discover valid models rather than guessing identifiers.

## 4. Verify Findings

Treat subagent output as hypotheses, not truth. The parent agent owns the final judgment.

For every material finding:

1. inspect the cited code and surrounding flow;
2. reproduce it with a focused test, command, or concrete reasoning where practical;
3. check it against user requirements and project guidance;
4. classify it as verified, rejected, already covered, or uncertain; and
5. avoid changing code for unverified stylistic preference.

Prioritize correctness and invariant violations over polish. Do not expand scope merely because a reviewer noticed unrelated cleanup.

In `review-only` mode, stop after verification and report findings without edits.

## 5. Apply the Smallest Coherent Fixes

For verified in-scope findings:

- preserve unrelated changes;
- fix the owning behavior rather than suppressing symptoms;
- follow established nearby patterns;
- add or improve behavior-focused tests when they increase confidence;
- avoid speculative abstractions and unrelated cleanup; and
- run focused validation after each meaningful correction.

After all corrections, rerun the relevant baseline checks. Add broader validation when the fixes increased the change's risk or reach.

## 6. Re-review, With a Bound

Run a second independent review only when the first pass produced code or structural changes that could introduce new issues. Focus the second pass on the resulting diff and previously identified risks.

Normally stop after at most two review passes. A third pass is justified only when the second pass discovers a new high-risk correctness issue in areas such as security, authorization, money, destructive data changes, or concurrency.

Stop when:

- there are no verified material findings;
- only unsupported preferences or unrelated improvements remain; or
- further progress is blocked on user clarification or unavailable infrastructure.

Do not repeat a clean review, chase a declaration of perfection, or allow mechanical review loops.

## 7. Final Report

Summarize concisely:

- **Scope reviewed:** branch/worktree range and major areas.
- **Findings fixed:** verified issues and corrections.
- **Findings rejected or deferred:** only material items, with reasons.
- **Validation:** exact checks and outcomes, including QA when performed.
- **Review passes:** number and the final review result.
- **Remaining uncertainty:** skipped checks, environment limitations, or unresolved questions.

Distinguish direct verification from reviewer opinion. Say that checks passed only for checks actually run. Do not claim the work is fully correct, production-ready, or ready to ship beyond the available evidence.
