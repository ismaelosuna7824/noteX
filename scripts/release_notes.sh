#!/usr/bin/env bash
#
# Builds release notes from the commits between two tags.
#
# GitHub's own `generate_release_notes` reads merged pull requests, and this
# repository pushes straight to main — so it had nothing to list and every
# release shipped with an empty body and a compare link. A reader who wants to
# know what changed should not have to open a diff.
#
# Usage: scripts/release_notes.sh <current-tag> [previous-tag]
set -euo pipefail

current="${1:?usage: release_notes.sh <current-tag> [previous-tag]}"
previous="${2:-$(git describe --tags --abbrev=0 "${current}^" 2>/dev/null || true)}"

range="${previous:+$previous..}$current"

# Subjects only, and no merges: a merge commit repeats what its children
# already say.
subjects=$(git log --no-merges --pretty=format:'%s' "$range")

# Conventional-commit types, in the order a reader cares about them. `chore`,
# `ci`, `test`, `refactor` and `style` are deliberately absent: they describe
# the repository, not the app someone just downloaded.
section() {
  local pattern="$1" heading="$2"
  local lines
  lines=$(printf '%s\n' "$subjects" |
    grep -E "^${pattern}(\([^)]*\))?!?: " || true)
  [ -n "$lines" ] || return 0

  printf '### %s\n\n' "$heading"
  printf '%s\n' "$lines" |
    # Drop the type prefix and capitalise: "feat(editor): a toolbar button"
    # reads as noise to anyone who is not reading the git history.
    sed -E "s/^${pattern}(\([^)]*\))?!?: //" |
    # perl, not `sed -E 's/^(.)/\U\1/'`: \U is a GNU extension, and BSD sed
    # on macOS emits a literal U instead — a script that quietly differs by
    # machine is worse than one that fails on both.
    perl -pe 's/^(.)/\u$1/' |
    sed 's/^/- /'
  printf '\n'
}

section 'feat' 'New'
section 'fix' 'Fixed'
section 'perf' 'Faster'
section 'docs' 'Documentation'

# Breaking changes are the one thing nobody may miss, so they are pulled out
# regardless of type and put where they cannot be scrolled past.
breaking=$(printf '%s\n' "$subjects" | grep -E '^[a-z]+(\([^)]*\))?!: ' || true)
if [ -n "$breaking" ]; then
  printf '### Breaking\n\n'
  printf '%s\n' "$breaking" |
    sed -E 's/^[a-z]+(\([^)]*\))?!: //' |
    perl -pe 's/^(.)/\u$1/' |
    sed 's/^/- /'
  printf '\n'
fi

printf '### Requirements\n\n'
printf -- '- macOS 11 or later · Windows 10 or later · Linux (Debian/Ubuntu)\n\n'

if [ -n "$previous" ]; then
  printf '**Full Changelog**: https://github.com/ismaelosuna7824/noteX/compare/%s...%s\n' \
    "$previous" "$current"
fi
