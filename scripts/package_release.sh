#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/package_release.sh [--version VERSION] [--output DIR]
       [--sign-identity IDENTITY] [--notary-profile PROFILE]

Builds a self-contained Apple Silicon zip. Signing is optional for local testing,
but --notary-profile requires a Developer ID Application signing identity.
EOF
}

version=""
output=""
sign_identity=""
notary_profile=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version|--output|--sign-identity|--notary-profile)
      [ "$#" -ge 2 ] || { echo "$1 requires a value" >&2; exit 64; }
      option="$1"
      value="$2"
      case "$option" in
        --version) version="$value" ;;
        --output) output="$value" ;;
        --sign-identity) sign_identity="$value" ;;
        --notary-profile) notary_profile="$value" ;;
      esac
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

[ -z "$notary_profile" ] || [ -n "$sign_identity" ] || {
  echo "--notary-profile requires --sign-identity." >&2
  exit 64
}

if [ -n "$sign_identity" ]; then
  /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F -- "$sign_identity" >/dev/null || {
    echo "The requested signing identity is not available in this keychain." >&2
    exit 1
  }
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
output=${output:-"$project_root/dist"}
mkdir -p "$output"
output=$(CDPATH= cd -- "$output" && pwd)

swift test --package-path "$project_root"
swift build --package-path "$project_root" -c release --arch arm64
bin_path=$(swift build --package-path "$project_root" -c release --arch arm64 --show-bin-path)
binary="$bin_path/macness"
/usr/bin/file "$binary" | /usr/bin/grep -q "arm64" || { echo "Release binary is not arm64." >&2; exit 1; }
binary_version=$("$binary" --version)
if [ -n "$version" ] && [ "$version" != "$binary_version" ]; then
  echo "Requested version $version does not match the binary version $binary_version." >&2
  exit 1
fi
version=${version:-$binary_version}
case "$version" in
  *[!0-9A-Za-z._-]*|'') echo "Version contains unsupported filename characters." >&2; exit 64 ;;
esac

package_name="macness-$version-macos-arm64"
stage=$(mktemp -d "${TMPDIR:-/tmp}/macness-package.XXXXXX")
archive_temp=""
archive_stage=""
checksum_temp=""
notary_result=""
cleanup() {
  /bin/rm -rf "$stage"
  [ -z "$archive_stage" ] || /bin/rm -rf "$archive_stage"
  [ -z "$checksum_temp" ] || /bin/rm -f "$checksum_temp"
  [ -z "$notary_result" ] || /bin/rm -f "$notary_result"
}
trap cleanup EXIT HUP INT TERM
package_root="$stage/$package_name"
mkdir -p "$package_root/bin"
/usr/bin/install -m 755 "$binary" "$package_root/bin/macness"
/usr/bin/install -m 755 "$project_root/scripts/install_release.sh" "$package_root/install.sh"
/bin/cp "$project_root/LICENSE" "$project_root/NOTICE" "$project_root/README.md" "$package_root/"
if [ -z "$sign_identity" ]; then
  /bin/cp "$project_root/UNSIGNED-DEVELOPER-BUILD.md" "$package_root/DISTRIBUTION.md"
else
  cat > "$package_root/DISTRIBUTION.md" <<'EOF'
# Developer ID build

The executable in this archive is signed with an Apple Developer ID Application certificate and the hardened runtime. Macness requests no signing entitlements.

If this archive was published as a production download, verify that the accompanying release record says Apple accepted its notarization submission. Zip archives and standalone executables cannot carry stapled notarization tickets, so the destination Mac must be online for Apple's first-run ticket lookup.
EOF
fi

if [ -n "$sign_identity" ]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$sign_identity" "$package_root/bin/macness"
  /usr/bin/codesign --verify --strict --verbose=2 "$package_root/bin/macness"
  /usr/bin/codesign -d --verbose=4 "$package_root/bin/macness" 2>&1 \
    | /usr/bin/grep -q '^Runtime Version=' || {
      echo "The signed executable does not report the hardened runtime." >&2
      exit 1
    }
fi

(cd "$package_root" && /usr/bin/shasum -a 256 bin/macness > SHA256SUMS)
/usr/bin/find "$package_root" -exec /usr/bin/touch -h -t 202601010000 {} +

archive="$output/$package_name.zip"
archive_stage=$(mktemp -d "$output/.macness-archive.XXXXXX")
archive_temp="$archive_stage/$package_name.zip"
(cd "$stage" && /usr/bin/zip -X -q "$archive_temp" \
  "$package_name/bin/macness" \
  "$package_name/install.sh" \
  "$package_name/LICENSE" \
  "$package_name/NOTICE" \
  "$package_name/README.md" \
  "$package_name/DISTRIBUTION.md" \
  "$package_name/SHA256SUMS")
/bin/mv -f "$archive_temp" "$archive"
archive_temp=""
checksum_temp=$(mktemp "$output/.$package_name.zip.sha256.XXXXXX")
(cd "$output" && /usr/bin/shasum -a 256 "$package_name.zip" > "$checksum_temp")
/bin/mv -f "$checksum_temp" "$archive.sha256"
checksum_temp=""

if [ -n "$notary_profile" ]; then
  notary_result=$(mktemp "$output/.$package_name.notarization.XXXXXX")
  /usr/bin/xcrun notarytool submit "$archive" \
    --keychain-profile "$notary_profile" \
    --wait \
    --output-format json > "$notary_result"
  notary_status=$(/usr/bin/plutil -extract status raw -o - "$notary_result")
  [ "$notary_status" = "Accepted" ] || {
    echo "Apple did not accept the notarization submission (status: $notary_status)." >&2
    exit 1
  }
  /bin/mv -f "$notary_result" "$archive.notarization.json"
  notary_result=""
  /usr/sbin/spctl --assess --type execute --verbose=4 "$package_root/bin/macness"
fi

echo "Package: $archive"
echo "Checksum: $archive.sha256"
if [ -n "$notary_profile" ]; then
  echo "Notarization: accepted ($archive.notarization.json)"
  echo "Stapling: not supported for a standalone executable distributed in a zip"
elif [ -n "$sign_identity" ]; then
  echo "Signing: Developer ID with hardened runtime; notarization not requested"
else
  echo "Signing: unsigned source/developer package"
fi
