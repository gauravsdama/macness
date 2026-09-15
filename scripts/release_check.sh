#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
mode=${1:-technical}
case "$mode" in
  technical|--publish) ;;
  *) echo "Usage: ./scripts/release_check.sh [--publish]" >&2; exit 64 ;;
esac

cd "$project_root"
git diff --check
swift test
swift build -c release
"$project_root/.build/release/macness" --help >/dev/null
test "$($project_root/.build/release/macness --version)" = "0.1.0"

if git grep -n '/Users/' -- . ':!scripts/release_check.sh'; then
  echo "Release check failed: a tracked personal home path was found." >&2
  exit 1
fi

if git ls-files | grep -Eq '(^|/)(\.macness|DerivedData|\.build|Packages)(/|$)'; then
  echo "Release check failed: generated output is tracked." >&2
  exit 1
fi

if [ "$mode" = "--publish" ] && [ ! -f LICENSE ]; then
  echo "Publish check failed: the repository owner has not selected a LICENSE." >&2
  exit 1
fi
if [ "$mode" = "--publish" ] && [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  echo "Publish check failed: the working tree is not clean." >&2
  exit 1
fi

echo "Macness technical release checks passed."
