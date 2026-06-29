#!/usr/bin/env bash
# Set local git author for Zero Insight repos (does not touch global config).
# Run from any directory:  bash config/git-author-setup.sh /path/to/repo [...]
#
# Optional: install the pre-commit hook in each repo:
#   cp config/pre-commit-check-author /path/to/repo/.git/hooks/pre-commit
#   chmod +x /path/to/repo/.git/hooks/pre-commit

set -euo pipefail

GIT_NAME="${GIT_NAME:-tearodactyl}"
GIT_EMAIL="${GIT_EMAIL:-tearodactylus@gmail.com}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/repo [/path/to/repo ...]" >&2
  exit 1
fi

for repo in "$@"; do
  if [[ ! -d "$repo/.git" ]]; then
    echo "skip (not a git repo): $repo" >&2
    continue
  fi
  git -C "$repo" config user.name "$GIT_NAME"
  git -C "$repo" config user.email "$GIT_EMAIL"
  echo "$repo -> $(git -C "$repo" config user.name) <$(git -C "$repo" config user.email)>"
done

echo "Done. Future commits in these repos use the identity above."
