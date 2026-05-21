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
  # pipx places binaries in $HOME/.local/bin. Some shells don't have that
  # on PATH by default — but the binary may already be installed there.
  # Prepend it BEFORE the existence check so we find pre-existing installs.
  export PATH="$HOME/.local/bin:$PATH"
  if command -v copier > /dev/null 2>&1; then return; fi
  if command -v pipx > /dev/null 2>&1; then
    echo "[init] Installing copier via pipx..."
    # `pipx install` may print "already installed" and return non-zero;
    # the post-install command -v check is the real verification.
    pipx install copier 2>&1 || true
    if command -v copier > /dev/null 2>&1; then return; fi
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

echo "[init] Rewriting .copier-answers.yml against the canonical upstream..."
# copier copy from a local path records `_src_path: .` and `_commit:
# <local-hash>`. After we delete copier.yml below, that local path is no
# longer a valid template, and the local commit hash isn't reachable from
# the upstream repo — so `copier update` would fail twice over.
#
# Point _src_path at the canonical upstream and replace _commit with the
# upstream's current HEAD (resolved via `git ls-remote`). Both can be
# overridden by env vars so this works for forks of the template.
UPSTREAM_URL="${OPENELIS_TEMPLATE_UPSTREAM:-https://github.com/DIGI-UW/openelis-distro-template.git}"
UPSTREAM_COPIER_PATH="${OPENELIS_TEMPLATE_COPIER_PATH:-gh:DIGI-UW/openelis-distro-template}"
ANSWERS="$ROOT/.copier-answers.yml"

UPSTREAM_COMMIT="$(git ls-remote "$UPSTREAM_URL" HEAD 2>/dev/null | cut -f1 || true)"
if [[ -z "$UPSTREAM_COMMIT" ]]; then
  echo "[init] WARN: could not resolve upstream HEAD (offline?). _commit will be" \
       "removed; set it manually to a valid upstream ref before 'copier update'."
fi

if [[ -f "$ANSWERS" ]]; then
  python3 - "$ANSWERS" "$UPSTREAM_COPIER_PATH" "${UPSTREAM_COMMIT:-}" <<'PY'
import sys, re
path, upstream, commit = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
# _src_path: replace or insert
text, n = re.subn(r'^_src_path:.*$', f'_src_path: {upstream}',
                  text, count=1, flags=re.MULTILINE)
if not n:
    text = f"_src_path: {upstream}\n" + text
# _commit: replace, insert, or remove
if commit:
    text, n = re.subn(r'^_commit:.*$', f'_commit: {commit}',
                      text, count=1, flags=re.MULTILINE)
    if not n:
        text = f"_commit: {commit}\n" + text
else:
    text = re.sub(r'^_commit:.*\n?', '', text, count=1, flags=re.MULTILINE)
open(path, "w", encoding="utf-8").write(text)
PY
fi

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
