# quality-gate

Runs deterministic checks over the git diff against HEAD plus untracked files, and over the project the working directory belongs to: well-formed JSON, YAML and TOML, the project's own lint, type and test commands (npm, ruff, mypy, pytest, go, cargo), `pre-commit`, and a secrets scan (gitleaks, or a regex scan when gitleaks is missing). It is fast, free and uses no LLM. It prints `GATE: PASS` or `GATE: FAIL` and exits 0 or 1.

## Install

For Claude Code, copy the skill folders into your personal skills directory:

```bash
git clone https://github.com/orenatobr/quality-gate.git
mkdir -p ~/.claude/skills
cp -R quality-gate/skills/* ~/.claude/skills/
mkdir -p ~/.claude/scripts
cp quality-gate/scripts/* ~/.claude/scripts/
chmod +x ~/.claude/scripts/*.sh
```

Start a new Claude Code session. Skills load from the `description` in each `SKILL.md`, so they trigger on their own and can also be called by name.

Other agents: each skill is a folder with a `SKILL.md` (YAML frontmatter plus Markdown). Tools that read the Agent Skills format can load `skills/` as it is. For the rest, paste the body of the `SKILL.md` into the agent's instruction file.

## Usage

Invoke `/quality-gate` before claiming work is done. Run it by hand with `~/.claude/scripts/quality-gate.sh --cwd <project>`.

## Requirements

`bash`, `git`, `jq` and `python3`. Optional: `gitleaks`, `pre-commit`, and whatever your project already uses to lint and test.

## Related skills

`llm-as-judge` runs after the gate passes.

## What is in this repo

| Path | Purpose |
|------|---------|
| `skills/quality-gate/` | The `quality-gate` skill. |
| `skills/prs-fixes/` | PR helper: apply review feedback and resolve threads. |
| `skills/prs-reviews/` | PR helper: post a Requested Changes review. |
| `scripts/` | Helper scripts that the skill calls. |
| `AGENTS.md` | Rules for AI agents that edit this repo. |

The two PR helpers ship in every repo of this family:

- `prs-fixes`: Applies the suggested fixes on one or more GitHub PRs, pushes them, replies to every review comment and resolves each thread. Example: `/prs-fixes 12, 15`.
- `prs-reviews`: Reviews one or more GitHub PRs and posts a Requested Changes review, one inline comment per finding, each with an exact location and a suggested change. Example: `/prs-reviews 12, 15`.

They need the `gh` CLI, and they call `git-guidelines`, `humanizer`, `programming-best-practices` and `attack-protection` when those skills are installed.

## Contributing

`main` is protected: changes land through a pull request with one approval. See [AGENTS.md](AGENTS.md) for the conventions.

## License

MIT, see [LICENSE](LICENSE).
