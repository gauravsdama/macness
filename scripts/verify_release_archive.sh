#!/bin/sh
set -eu

usage() {
  echo "Usage: ./scripts/verify_release_archive.sh ARCHIVE [CHECKSUM_FILE]" >&2
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { usage; exit 64; }
archive=$1
checksum_file=${2:-"$archive.sha256"}
[ -f "$archive" ] || { echo "Archive not found: $archive" >&2; exit 1; }
[ -f "$checksum_file" ] || { echo "Checksum not found: $checksum_file" >&2; exit 1; }

archive_dir=$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd)
checksum_path=$(CDPATH= cd -- "$(dirname -- "$checksum_file")" && pwd)/$(basename -- "$checksum_file")
stage=$(mktemp -d "${TMPDIR:-/tmp}/macness-verify.XXXXXX")
cleanup() { /bin/rm -rf "$stage"; }
trap cleanup EXIT HUP INT TERM

(cd "$archive_dir" && /usr/bin/shasum -a 256 -c "$checksum_path")
/usr/bin/unzip -t "$archive" >/dev/null
/usr/bin/unzip -q "$archive" -d "$stage/unpacked"

package_root=$(/usr/bin/find "$stage/unpacked" -mindepth 1 -maxdepth 1 -type d | /usr/bin/head -n 1)
[ -n "$package_root" ] || { echo "Archive has no package directory." >&2; exit 1; }

actual_manifest=$(cd "$package_root" && /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort)
expected_manifest='./DISTRIBUTION.md
./LICENSE
./NOTICE
./README.md
./SHA256SUMS
./bin/macness
./install.sh'
[ "$actual_manifest" = "$expected_manifest" ] || {
  echo "Archive contents do not match the release manifest." >&2
  printf '%s\n' "$actual_manifest" >&2
  exit 1
}

(cd "$package_root" && /usr/bin/shasum -a 256 -c SHA256SUMS)
/usr/bin/file "$package_root/bin/macness" | /usr/bin/grep -q 'arm64' || {
  echo "Packaged executable is not arm64." >&2
  exit 1
}

version=$("$package_root/bin/macness" --version)
prefix="$stage/prefix"
"$package_root/install.sh" --prefix "$prefix"
[ "$("$prefix/bin/macness" --version)" = "$version" ]
"$prefix/bin/macness" doctor --json > "$stage/doctor.json"
/usr/bin/plutil -convert xml1 -o /dev/null "$stage/doctor.json"

echo "Verified Macness $version archive, offline install, and relocated launch."
echo "Architecture: arm64"
/usr/bin/codesign -dvv "$prefix/bin/macness" 2>&1 \
  | /usr/bin/grep -E '^(Authority|Signature|TeamIdentifier|Runtime Version)=' || true
