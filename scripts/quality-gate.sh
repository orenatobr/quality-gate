#!/usr/bin/env bash
# Deterministic quality gate: schema, lint/types/tests, secrets.
# Runs over the files changed in the current git repo (diff vs HEAD plus
# untracked) and the project the cwd belongs to. Fast, free, no LLM.
# Writes <state>/gate.json ({turn, pass, checks, ts}); exit 0 = pass, 1 = fail.
# Usage: quality-gate.sh [--state DIR] [--turn ID] [--cwd DIR]
set -u
PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=feedback-loop-lib.sh
source "$SCRIPT_DIR/feedback-loop-lib.sh"

state="/tmp/qjs-manual"; turn="manual"; cwd="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    --turn) turn="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$state"
cd "$cwd" || { echo "quality-gate: cwd not found: $cwd" >&2; exit 2; }

checks_file="$(mktemp)"
trap 'rm -f "$checks_file"' EXIT
add_check() { jq -nc --arg n "$1" --arg s "$2" --arg d "$3" '{name:$n,status:$s,detail:$d}' >> "$checks_file"; }

# Changed files, relative to the git root (diff HEAD, falling back to the
# index on a repo with no commits yet, plus untracked-not-ignored).
root=""; changed=""
if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  changed="$({ git -C "$root" diff --name-only HEAD 2>/dev/null || git -C "$root" diff --name-only --cached 2>/dev/null
               git -C "$root" ls-files --others --exclude-standard 2>/dev/null; } | sort -u | sed '/^$/d')"
fi

check_schema() {
  if [ -z "$changed" ]; then add_check schema na "no changed files"; return; fi
  bad=""; n=0
  while IFS= read -r f; do
    p="$root/$f"; [ -f "$p" ] || continue
    case "$f" in
      # ponytail: these formats allow comments, so strict JSON parsing would false-fail them
      */tsconfig*.json|tsconfig*.json|*/jsconfig*.json|jsconfig*.json|*.jsonc|*/.eslintrc*|.eslintrc*|*/.vscode/*|.vscode/*) continue ;;
      *.json) n=$((n+1)); err="$(jq empty "$p" 2>&1)" || bad="${bad}${f}: ${err}"$'\n' ;;
      *.yaml|*.yml)
        n=$((n+1))
        err="$(python3 -I -c 'import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
list(yaml.safe_load_all(open(sys.argv[1])))' "$p" 2>&1)" || bad="${bad}${f}: $(printf '%s' "$err" | tail -n 1)"$'\n' ;;
      *.toml)
        n=$((n+1))
        err="$(python3 -I -c 'import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)
tomllib.load(open(sys.argv[1], "rb"))' "$p" 2>&1)" || bad="${bad}${f}: $(printf '%s' "$err" | tail -n 1)"$'\n' ;;
    esac
  done <<< "$changed"
  if [ -n "$bad" ]; then add_check schema fail "$bad"
  elif [ "$n" -eq 0 ]; then add_check schema na "no json/yaml/toml among changed files"
  else add_check schema ok "$n file(s) well-formed (syntax only)"; fi
}

check_project() {
  if ! find_project_root "$cwd"; then
    add_check lint-types-tests na "no project marker (package.json, pyproject.toml, go.mod, Cargo.toml) above $cwd"
    return
  fi
  cd "$project_root" || { add_check lint-types-tests na "cannot enter $project_root"; return; }
  run_checks
  cd "$cwd" || true
  if [ -n "$failures" ]; then add_check lint-types-tests fail "$(printf '%b' "$failures")"
  else add_check lint-types-tests ok "$marker project at $project_root"; fi
}

check_precommit() {
  if [ -z "$changed" ] || [ ! -f "$root/.pre-commit-config.yaml" ] || ! command -v pre-commit >/dev/null 2>&1; then
    add_check pre-commit na "no changed files, no .pre-commit-config.yaml, or pre-commit not installed"
    return
  fi
  out_file="$(mktemp)"
  files=(); while IFS= read -r f; do [ -f "$root/$f" ] && files+=("$f"); done <<< "$changed"
  # pre-commit may reformat files and exit 1 on the first run; the second run then passes.
  ( cd "$root" && run_with_timeout 120 pre-commit run --files "${files[@]}" ); rc=$?
  if [ "$rc" -eq 0 ]; then add_check pre-commit ok "hooks passed on ${#files[@]} file(s)"
  else add_check pre-commit fail "exit $rc"$'\n'"$(tail -c 3000 "$out_file")"; fi
  rm -f "$out_file"
}

check_secrets() {
  if [ -z "$changed" ]; then add_check secrets na "no changed files"; return; fi
  hits=""
  # Versioned env files (templates are fine).
  while IFS= read -r f; do
    case "$f" in
      *.env.example|*.env.sample|*.env.template) ;;
      .env|.env.*|*/.env|*/.env.*) hits="${hits}${f}: env file in the change set"$'\n' ;;
    esac
  done <<< "$changed"
  if command -v gitleaks >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    # Copy only the changed files so gitleaks scans exactly them.
    printf '%s\n' "$changed" | tar -C "$root" -cf - -T - 2>/dev/null | tar -C "$tmp" -xf - 2>/dev/null
    gl="$(gitleaks detect --no-git --source "$tmp" --no-banner --redact 2>&1)" || hits="${hits}gitleaks: $(printf '%s' "$gl" | tail -n 15)"$'\n'
    rm -rf "$tmp"
    engine="gitleaks"
  else
    # ponytail: regex scan has a coverage ceiling, install gitleaks (brew install gitleaks) for real coverage
    engine="regex (gitleaks not installed)"
    pats=(
      'aws-key::AKIA[0-9A-Z]{16}'
      'github-token::gh[pousr]_[A-Za-z0-9]{36}'
      'github-pat::github_pat_[A-Za-z0-9_]{22,}'
      'sk-key::(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}'
      'slack-token::xox[baprs]-[A-Za-z0-9-]{10,}'
      'google-key::AIza[0-9A-Za-z_-]{35}'
      'private-key::-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
    )
    while IFS= read -r f; do
      p="$root/$f"; [ -f "$p" ] || continue
      for entry in "${pats[@]}"; do
        # Report file and line only, never the matched value.
        lines="$(grep -nIE -e "${entry#*::}" "$p" 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')"
        [ -n "$lines" ] && hits="${hits}${f}:${lines}: possible secret (${entry%%::*})"$'\n'
      done
    done <<< "$changed"
  fi
  if [ -n "$hits" ]; then add_check secrets fail "$hits"
  else add_check secrets ok "scanned changed files with $engine"; fi
}

check_schema
check_project
check_precommit
check_secrets

tmp_json="$(mktemp "$state/.gate.XXXXXX")"
jq -s --arg turn "$turn" --arg ts "$(date -u +%FT%TZ)" \
  '{turn:$turn, pass:(all(.[]; .status != "fail")), checks:., ts:$ts}' "$checks_file" > "$tmp_json" \
  && mv "$tmp_json" "$state/gate.json"

jq -r '.checks[] | "\(.name): \(.status)" + (if .status == "fail" then "\n" + .detail else "" end)' "$state/gate.json"
if [ "$(jq -r '.pass' "$state/gate.json")" = "true" ]; then echo "GATE: PASS"; exit 0; fi
echo "GATE: FAIL"; exit 1
