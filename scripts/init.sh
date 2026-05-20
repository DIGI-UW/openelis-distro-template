#!/usr/bin/env bash
# Initialize this distro after cloning a "Use this template" copy.
#
# Renders the .jinja files in place against your answers, runs the
# post-generate tasks (random secrets, profile merge), and removes the
# template-only scaffolding so the repo is a self-contained distro.
#
# Usage:
#   ./scripts/init.sh                     # interactive prompts
#   ./scripts/init.sh --defaults          # accept all demo defaults
#   ./scripts/init.sh --data context_slug=png \
#       --data 'context_name=Papua New Guinea' --defaults
#
# Anything passed to this script is forwarded to `copier copy`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f copier.yml ]]; then
  echo "init.sh: copier.yml not found — this repo is already initialized." >&2
  exit 1
fi

ensure_copier() {
  if command -v copier > /dev/null 2>&1; then return; fi
  if command -v pipx > /dev/null 2>&1; then
    echo "[init] Installing copier via pipx..."
    pipx install copier
    export PATH="$HOME/.local/bin:$PATH"
    command -v copier > /dev/null 2>&1 && return
  fi
  cat <<'EOF' >&2
init.sh: copier is required and isn't installed.

Install it first, then re-run ./scripts/init.sh:
  pipx install copier        # preferred
  pip install --user copier

EOF
  exit 1
}
ensure_copier

TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo "[init] Rendering template into $TMP..."
copier copy --trust "$ROOT" "$TMP" "$@"

echo "[init] Syncing rendered output back over $ROOT..."
# rsync preserves perms (the executable bit on scripts/*.sh).
# Exclude .git so any existing history is preserved.
rsync -a --exclude='.git/' "$TMP/" "$ROOT/"

echo "[init] Removing template scaffolding..."
# .jinja source files — the rendered counterparts have just been written.
find "$ROOT" -name '*.jinja' -type f -delete
# Template-only files that don't belong to a generated distro.
rm -f "$ROOT/copier.yml" "$ROOT/CREATING-A-DISTRO.md"
rm -rf "$ROOT/tools/copier_tasks"
# pr.yml exercises copier against the template; the new distro shouldn't
# inherit that CI. Generated distros get release.yml instead.
rm -f "$ROOT/.github/workflows/pr.yml"

echo "[init] Removing init.sh (self)..."
rm -- "$0"

cat <<'EOF'

Done. This repo is now a self-contained distro.

Next steps:
  cp .env.example .env
  docker compose up -d
  open http://localhost:8080/OpenELIS-Global/

When ready, commit the initialized state:
  git add -A
  git commit -m "chore: initialize from openelis-distro-template"
EOF
