#!/usr/bin/env bash
# Shared helpers for feedback-loop.sh (PostToolUse) and
# feedback-loop-stop.sh (Stop): find the project a path belongs to and run
# whatever lint/typecheck/test commands that project already exposes.

# ponytail: no `timeout`/`gtimeout` on this machine, so roll a minimal one.
run_with_timeout() {
  secs="$1"; shift
  "$@" > "$out_file" 2>&1 &
  cmd_pid=$!
  ( sleep "$secs" && kill -TERM "$cmd_pid" 2>/dev/null ) &
  watchdog_pid=$!
  wait "$cmd_pid" 2>/dev/null
  status=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  return $status
}

# Sets project_root and marker as a side effect; leaves both empty if none found.
find_project_root() {
  dir="$1"
  project_root=""
  marker=""
  while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
    for m in package.json pyproject.toml go.mod Cargo.toml; do
      if [ -f "$dir/$m" ]; then
        project_root="$dir"
        marker="$m"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done
  return 1
}

try_cmd() {
  label="$1"; shift
  run_with_timeout 90 "$@"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    body="$(tail -c 4000 "$out_file")"
    failures="${failures}\n### ${label} (exit ${rc})\n${body}\n"
  fi
}

# Requires project_root/marker set (find_project_root) and cwd already
# changed into project_root. Sets failures as a side effect.
run_checks() {
  failures=""
  out_file="$(mktemp)"
  trap 'rm -f "$out_file"' RETURN

  case "$marker" in
    package.json)
      has_script() { jq -e --arg s "$1" '.scripts[$s]' package.json >/dev/null 2>&1; }
      has_script lint && try_cmd "npm run lint" npm run lint --silent
      if has_script typecheck; then
        try_cmd "npm run typecheck" npm run typecheck --silent
      elif has_script type-check; then
        try_cmd "npm run type-check" npm run type-check --silent
      elif [ -f tsconfig.json ]; then
        try_cmd "tsc --noEmit" npx --no-install tsc --noEmit
      fi
      has_script test && try_cmd "npm test" npm test --silent
      ;;
    pyproject.toml)
      if grep -q '\[tool.ruff\]' pyproject.toml 2>/dev/null || [ -f ruff.toml ] || [ -f .ruff.toml ]; then
        try_cmd "ruff check" ruff check .
      fi
      if grep -q '\[tool.mypy\]' pyproject.toml 2>/dev/null || [ -f mypy.ini ]; then
        try_cmd "mypy" mypy .
      fi
      if grep -q '\[tool.pytest' pyproject.toml 2>/dev/null || [ -d tests ]; then
        try_cmd "pytest" pytest -q
      fi
      ;;
    go.mod)
      try_cmd "go vet" go vet ./...
      try_cmd "go build" go build ./...
      try_cmd "go test" go test ./...
      ;;
    Cargo.toml)
      try_cmd "cargo check" cargo check
      try_cmd "cargo test" cargo test
      ;;
  esac
}
