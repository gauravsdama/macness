#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh [--check] [--prefix DIR] [--codex-home DIR] [--no-codex-skill]

Builds and installs macness into DIR/bin (default: $HOME/.local/bin) and
installs the bundled Codex skill into $CODEX_HOME/skills/macness
(default: $HOME/.codex).

Options:
  --check             Validate prerequisites and permissions without installing globally.
  --prefix DIR        Installation prefix. The executable is placed in DIR/bin.
  --codex-home DIR    Codex home containing skills/ (default: $CODEX_HOME or $HOME/.codex).
  --no-codex-skill    Do not install the Codex skill.
  -h, --help          Show this help.
EOF
}

prefix="${HOME}/.local"
check_only=false
install_codex_skill=true
codex_home="${CODEX_HOME:-${HOME}/.codex}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check_only=true ;;
    --prefix)
      [ "$#" -ge 2 ] || { echo "--prefix requires a directory" >&2; exit 64; }
      prefix="$2"
      shift
      ;;
    --no-codex-skill) install_codex_skill=false ;;
    --codex-home)
      [ "$#" -ge 2 ] || { echo "--codex-home requires a directory" >&2; exit 64; }
      codex_home="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

for command in swift xcodebuild; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [ "$check_only" = true ]; then
  swift run --package-path "$project_root" macness doctor
  exit 0
fi

swift build --package-path "$project_root" -c release
mkdir -p "$prefix/bin"
install -m 755 "$project_root/.build/release/macness" "$prefix/bin/macness"

if [ "$install_codex_skill" = true ]; then
  skill_target="$codex_home/skills/macness"
  mkdir -p "$skill_target"
  cp "$project_root/codex/skills/macness/SKILL.md" "$skill_target/SKILL.md"
  echo "Installed Codex skill: $skill_target/SKILL.md"
fi

echo "Installed executable: $prefix/bin/macness"
echo "Ensure this is on PATH: export PATH=\"$prefix/bin:\$PATH\""
echo "Open a new Codex task after installation so it can discover the local skill."
