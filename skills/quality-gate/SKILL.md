---
name: quality-gate
description: Use when finishing a turn, before claiming work is done, or when a Stop hook asks for it. Runs the deterministic checks (schema, lint, types, tests, pre-commit, secrets scan) over the changed files and the current project. Fast, free, no LLM. Trigger on /quality-gate, "quality gate", "run checks", "gate".
---

# /quality-gate

Deterministic checks only. They are fast, free and cannot hallucinate. The LLM judge (`/llm-as-judge`) runs after this one, never before. Never use em dashes.

## Run

Use the exact command the Stop hook gave you (it carries `--state`, `--turn` and `--cwd`). With no hook, run it bare:

```bash
~/.claude/scripts/quality-gate.sh
```

Use a Bash timeout of 300000 ms: test suites can be slow.

## What it checks

Over the git diff vs HEAD plus untracked files, and the project the cwd belongs to:

- **schema:** json, yaml and toml files are well-formed (syntax only; files that allow comments, like tsconfig, are skipped).
- **lint-types-tests:** the project's own lint, typecheck and test commands (npm, ruff, mypy, pytest, go, cargo).
- **pre-commit:** `pre-commit run --files <changed>` when `.pre-commit-config.yaml` exists.
- **secrets:** gitleaks when installed, otherwise a regex scan for common key formats and versioned `.env` files.

A check with nothing to do reports `na`, and the gate still passes.

## When it fails

1. Read the failing check's detail. Fix the root cause in the code.
2. Never edit a test just to make it pass, never silence a lint rule, never delete the finding.
3. If pre-commit reformatted files and exited 1, run the gate again.
4. A secret hit means rotate the key, not just delete the line.
5. Rerun until `GATE: PASS`.

## Report

One line per check as the script prints it, for example `schema: ok | lint-types-tests: ok | pre-commit: na | secrets: ok`. Say pass only when the command printed `GATE: PASS` (exit 0). Do not call the judge from here; the order is gate first, judge second.
