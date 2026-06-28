#!/usr/bin/env bash
# First-time publish of a local git repo to GitHub as a public (or private) remote.
#
# Usage: ./gh-init.sh [options]
#
# Exits with an error if origin already exists or the GitHub repo name is taken.
set -euo pipefail

DRY_RUN=0
VISIBILITY="public"
REPO_NAME=""
DESCRIPTION=""

usage() {
  cat <<'EOF'
Usage: ./gh-init.sh [options]

Create a GitHub repository and push the current branch (first-time publish only).

Options:
  --name NAME           GitHub repo name (default: directory name)
  --description TEXT    Repo description (default: empty)
  --private             Create private repo instead of public
  --dry-run             Print planned commands without executing
  -h, --help            Show this help

Requires: git, GitHub CLI (gh) authenticated via `gh auth login`
EOF
}

print_summary() {
  local url="$1"
  local visibility="$2"
  local default_branch="$3"
  local origin_url="$4"

  echo ""
  echo "## Summary"
  echo ""
  echo "URL: $url"
  echo "Visibility: $visibility"
  echo "Default branch: $default_branch"
  echo "Remote: origin → $origin_url"
  echo ""
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      REPO_NAME="${2:?--name requires a value}"
      shift 2
      ;;
    --description)
      DESCRIPTION="${2:?--description requires a value}"
      shift 2
      ;;
    --private)
      VISIBILITY="private"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository." >&2
  exit 1
}
cd "$REPO_ROOT"

if [[ -z "$REPO_NAME" ]]; then
  REPO_NAME="$(basename "$REPO_ROOT")"
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Error: detached HEAD — checkout a branch before publishing." >&2
  exit 1
fi

# Step 1: Guard — origin must not exist
if git remote get-url origin >/dev/null 2>&1; then
  echo "Error: origin remote already exists. This script is for first-time publish only." >&2
  echo "Use \`git push\` to push updates." >&2
  exit 1
fi

# Step 2: gh auth
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh is not installed. Install from https://cli.github.com/" >&2
  exit 1
fi
if [[ "$DRY_RUN" -eq 0 ]] && ! gh auth status >/dev/null 2>&1; then
  echo "Error: not authenticated. Run: gh auth login -h github.com" >&2
  exit 1
fi

# Step 3: Resolve owner
if [[ "$DRY_RUN" -eq 1 ]]; then
  OWNER="${GITHUB_USER:-YOUR_GITHUB_USER}"
else
  OWNER="$(gh api user -q .login)"
fi

FULL_REPO="$OWNER/$REPO_NAME"

# Step 4: Check repo does not exist on GitHub
if [[ "$DRY_RUN" -eq 0 ]]; then
  if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
    echo "Error: GitHub repo $FULL_REPO already exists." >&2
    exit 1
  fi
fi

# Step 5: Create repo and push
VIS_FLAG="--public"
if [[ "$VISIBILITY" == "private" ]]; then
  VIS_FLAG="--private"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_summary \
    "https://github.com/$FULL_REPO" \
    "$(echo "$VISIBILITY" | tr '[:lower:]' '[:upper:]')" \
    "$CURRENT_BRANCH" \
    "https://github.com/$FULL_REPO.git"
  exit 0
fi

if [[ -n "$DESCRIPTION" ]]; then
  gh repo create "$REPO_NAME" $VIS_FLAG --source=. --remote=origin --push --description "$DESCRIPTION" >/dev/null
else
  gh repo create "$REPO_NAME" $VIS_FLAG --source=. --remote=origin --push >/dev/null
fi

# Step 6: Verify
REPO_URL="$(gh repo view "$FULL_REPO" --json url -q .url)"
REPO_VISIBILITY="$(gh repo view "$FULL_REPO" --json visibility -q .visibility)"
DEFAULT_BRANCH="$(gh repo view "$FULL_REPO" --json defaultBranchRef -q .defaultBranchRef.name)"
ORIGIN_URL="$(git remote get-url origin)"

if [[ "$VISIBILITY" == "public" && "$REPO_VISIBILITY" != "PUBLIC" ]]; then
  echo "Error: expected PUBLIC visibility but got $REPO_VISIBILITY" >&2
  exit 1
fi

print_summary "$REPO_URL" "$REPO_VISIBILITY" "$DEFAULT_BRANCH" "$ORIGIN_URL"
