#!/bin/sh
set -eu

usage() {
  echo "Usage: ./install.sh [--prefix DIR]" >&2
}

prefix="${HOME}/.local"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || { echo "--prefix requires a directory" >&2; exit 64; }
      prefix="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 64 ;;
  esac
  shift
done

[ "$(uname -s)" = "Darwin" ] || { echo "Macness requires macOS." >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "This package supports Apple Silicon (arm64) Macs only." >&2; exit 1; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
(cd "$script_dir" && /usr/bin/shasum -a 256 -c SHA256SUMS)

mkdir -p "$prefix/bin"
/usr/bin/install -m 755 "$script_dir/bin/macness" "$prefix/bin/macness"
"$prefix/bin/macness" --version

echo "Installed Macness at $prefix/bin/macness"
echo "Add it to PATH with: export PATH=\"$prefix/bin:\$PATH\""
echo "Then run: macness doctor --json"
