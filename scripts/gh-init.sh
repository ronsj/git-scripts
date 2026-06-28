#!/usr/bin/env bash
# First-time publish of a local git repo to GitHub as a public (or private) remote.
#
# Usage: ./gh-init.sh [options]
#
# Exits with an error if origin already exists or the GitHub repo name is taken.
# Prints a command report when finished.
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

log_cmd() {
  echo ""
  echo "### $1"
  echo ""
  echo '```bash'
  echo "$2"
  echo '```'
  if [[ "$3" != "" ]]; then
    echo ""
    echo "**Result:** $3"
  fi
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

echo "# GitHub Publish Report"
echo ""
echo "Repository root: $REPO_ROOT"
echo "Repo name: $REPO_NAME"
echo "Visibility: $VISIBILITY"
echo "Branch: $CURRENT_BRANCH"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Mode: dry run"
fi

# Step 1: Guard — origin must not exist
ORIGIN_CHECK_CMD="git remote get-url origin"
if git remote get-url origin >/dev/null 2>&1; then
  ORIGIN_URL="$(git remote get-url origin)"
  log_cmd "1. Guard: check origin remote" "$ORIGIN_CHECK_CMD" "origin already configured ($ORIGIN_URL)"
  echo "" >&2
  echo "Error: origin remote already exists. This script is for first-time publish only." >&2
  echo "Use \`git push\` to push updates." >&2
  exit 1
fi
log_cmd "1. Guard: check origin remote" "$ORIGIN_CHECK_CMD" "no origin remote (ok)"

# Step 2: gh auth
GH_AUTH_CMD="gh auth status"
if [[ "$DRY_RUN" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh is not installed." >&2
    exit 1
  fi
  log_cmd "2. Verify GitHub CLI authentication" "$GH_AUTH_CMD" "[DRY RUN] skipped"
else
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh is not installed. Install from https://cli.github.com/" >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    log_cmd "2. Verify GitHub CLI authentication" "$GH_AUTH_CMD" "FAILED"
    echo "" >&2
    echo "Error: not authenticated. Run: gh auth login -h github.com" >&2
    exit 1
  fi
  GH_AUTH_OUT="$(gh auth status 2>&1)"
  log_cmd "2. Verify GitHub CLI authentication" "$GH_AUTH_CMD" "$GH_AUTH_OUT"
fi

# Step 3: Resolve owner
OWNER_CMD="gh api user -q .login"
if [[ "$DRY_RUN" -eq 1 ]]; then
  OWNER="${GITHUB_USER:-YOUR_GITHUB_USER}"
  log_cmd "3. Resolve GitHub owner" "$OWNER_CMD" "[DRY RUN] assumed owner: $OWNER"
else
  OWNER="$(gh api user -q .login)"
  log_cmd "3. Resolve GitHub owner" "$OWNER_CMD" "$OWNER"
fi

FULL_REPO="$OWNER/$REPO_NAME"

# Step 4: Check repo does not exist on GitHub
REPO_VIEW_CMD="gh repo view $FULL_REPO"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log_cmd "4. Check repo does not exist on GitHub" "$REPO_VIEW_CMD" "[DRY RUN] skipped"
else
  if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
    log_cmd "4. Check repo does not exist on GitHub" "$REPO_VIEW_CMD" "repository already exists"
    echo "" >&2
    echo "Error: GitHub repo $FULL_REPO already exists." >&2
    exit 1
  fi
  log_cmd "4. Check repo does not exist on GitHub" "$REPO_VIEW_CMD" "not found (ok)"
fi

# Step 5: Create repo and push
VIS_FLAG="--public"
if [[ "$VISIBILITY" == "private" ]]; then
  VIS_FLAG="--private"
fi

CREATE_PART="gh repo create \"$REPO_NAME\" $VIS_FLAG --source=. --remote=origin --push"
if [[ -n "$DESCRIPTION" ]]; then
  CREATE_CMD="$CREATE_PART --description \"$DESCRIPTION\""
else
  CREATE_CMD="$CREATE_PART"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_cmd "5. Create GitHub repo and push" "$CREATE_CMD" "[DRY RUN] skipped"
else
  CREATE_OUT=""
  if [[ -n "$DESCRIPTION" ]]; then
    CREATE_OUT="$(gh repo create "$REPO_NAME" $VIS_FLAG --source=. --remote=origin --push --description "$DESCRIPTION" 2>&1)"
  else
    CREATE_OUT="$(gh repo create "$REPO_NAME" $VIS_FLAG --source=. --remote=origin --push 2>&1)"
  fi
  log_cmd "5. Create GitHub repo and push" "$CREATE_CMD" "$CREATE_OUT"
fi

# Step 6: Verify
VERIFY_CMD="gh repo view $FULL_REPO --json name,visibility,url,defaultBranchRef"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log_cmd "6. Verify remote and visibility" "$VERIFY_CMD" "[DRY RUN] skipped"
  echo ""
  echo "## Summary"
  echo ""
  echo "| Field | Value |"
  echo "|---|---|"
  echo "| URL | https://github.com/$FULL_REPO |"
  echo "| Visibility | $(echo "$VISIBILITY" | tr '[:lower:]' '[:upper:]') |"
  echo "| Default branch | $CURRENT_BRANCH |"
  echo "| Remote | origin → https://github.com/$FULL_REPO.git |"
  echo ""
  echo "Future pushes: \`git push\`"
  exit 0
fi

VERIFY_JSON="$(gh repo view "$FULL_REPO" --json name,visibility,url,defaultBranchRef)"
log_cmd "6. Verify remote and visibility" "$VERIFY_CMD" "$VERIFY_JSON"

REPO_URL="$(gh repo view "$FULL_REPO" --json url -q .url)"
REPO_VISIBILITY="$(gh repo view "$FULL_REPO" --json visibility -q .visibility)"
DEFAULT_BRANCH="$(gh repo view "$FULL_REPO" --json defaultBranchRef -q .defaultBranchRef.name)"

ORIGIN_URL="$(git remote get-url origin)"

if [[ "$VISIBILITY" == "public" && "$REPO_VISIBILITY" != "PUBLIC" ]]; then
  echo "Error: expected PUBLIC visibility but got $REPO_VISIBILITY" >&2
  exit 1
fi

echo ""
echo "## Summary"
echo ""
echo "URL: $REPO_URL"
echo "Visibility: $REPO_VISIBILITY"
echo "Default branch: $DEFAULT_BRANCH"
echo "Remote: origin → $ORIGIN_URL"
echo ""
