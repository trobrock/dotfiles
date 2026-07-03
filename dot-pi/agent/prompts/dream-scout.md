---
description: Read-only scout for high-confidence maintenance opportunities
argument-hint: "[recipe]"
---
Run a read-only dream scout for this repository.

Recipe: ${1:-general}

Rules:
- Do not edit files.
- Do not read secret-looking files: .env*, credentials, secrets, auth.json, private keys, .ssh, .gnupg.
- Identify high-confidence, low-risk, useful work only.
- Prefer concrete evidence from tests, docs, config, git history, TODO/FIXME comments, and local validation commands.
- Omit vague refactors or speculative improvements.

Return a ranked list of candidate work items. For each candidate include:
- title
- confidence / impact / risk
- exact evidence with paths and lines
- files involved
- proposed minimal work
- validation command or check
- whether autonomous patching would be safe
