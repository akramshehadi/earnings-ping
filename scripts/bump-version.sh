#!/usr/bin/env bash
#
# Bump the app version in project.yml, the single source of truth.
#
#   MARKETING_VERSION       -> CFBundleShortVersionString  (SemVer, user-facing)
#   CURRENT_PROJECT_VERSION -> CFBundleVersion             (monotonic build number)
#
# Versioning policy (issue 08):
#   * MARKETING_VERSION follows SemVer (MAJOR.MINOR.PATCH).
#   * CURRENT_PROJECT_VERSION only ever increases — bump it on EVERY release so
#     Sparkle/Gatekeeper can always order builds, even reissues of one version.
#
# Usage:
#   scripts/bump-version.sh patch    # 0.1.0 -> 0.1.1, build +1
#   scripts/bump-version.sh minor    # 0.1.1 -> 0.2.0, build +1
#   scripts/bump-version.sh major    # 0.2.0 -> 1.0.0, build +1
#   scripts/bump-version.sh build    # marketing version unchanged, build +1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SPEC="project.yml"

part="${1:-}"
case "$part" in
  major|minor|patch|build) ;;
  *) echo "usage: $0 {major|minor|patch|build}" >&2; exit 2 ;;
esac

cur_marketing="$(/usr/bin/awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$SPEC")"
cur_build="$(/usr/bin/awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$SPEC")"

IFS='.' read -r major minor patch <<<"$cur_marketing"
: "${major:=0}" "${minor:=0}" "${patch:=0}"

case "$part" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  build) ;;  # marketing version unchanged
esac
new_marketing="${major}.${minor}.${patch}"
new_build=$((cur_build + 1))

# BSD/macOS sed in-place edit; the values are quoted in the spec.
/usr/bin/sed -i '' \
  -e "s/MARKETING_VERSION: \"${cur_marketing}\"/MARKETING_VERSION: \"${new_marketing}\"/" \
  -e "s/CURRENT_PROJECT_VERSION: \"${cur_build}\"/CURRENT_PROJECT_VERSION: \"${new_build}\"/" \
  "$SPEC"

echo "MARKETING_VERSION:       ${cur_marketing} -> ${new_marketing}"
echo "CURRENT_PROJECT_VERSION: ${cur_build} -> ${new_build}"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null
echo "==> Done. Commit project.yml to record the bump."
