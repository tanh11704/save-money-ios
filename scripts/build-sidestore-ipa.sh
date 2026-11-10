#!/bin/bash
# Build for physical iPhone/iPad; SideStore supplies the signature on installation.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out_dir="$repo_dir/build/SideStore"
mkdir -p "$out_dir"

if ! xcodebuild -project "$repo_dir/SaveMoney.xcodeproj" \
    -target SaveMoney -configuration Release -sdk iphoneos \
    SYMROOT="$out_dir/products" OBJROOT="$out_dir/objects" \
    CODE_SIGNING_ALLOWED=NO build > "$out_dir/build.log" 2>&1; then
    tail -n 50 "$out_dir/build.log"
    exit 1
fi

app_dir="$out_dir/products/Release-iphoneos/SaveMoney.app"
executable="$app_dir/SaveMoney"
test -f "$executable"
# Never accidentally distribute a Simulator build as an IPA.
xcrun vtool -show-build "$executable" > "$out_dir/platform.txt"
if ! /usr/bin/grep -Eq 'platform[[:space:]]+IOS$' "$out_dir/platform.txt"; then
    echo "Expected platform IOS; see $out_dir/platform.txt" >&2
    exit 1
fi
if ! /usr/bin/lipo -archs "$executable" | /usr/bin/grep -qw arm64; then
    echo "Expected arm64 device binary." >&2
    exit 1
fi

stage_dir="$(mktemp -d "$out_dir/staging.XXXXXX")"
trap 'rm -rf -- "$stage_dir"' EXIT
mkdir "$stage_dir/Payload"
/usr/bin/ditto "$app_dir" "$stage_dir/Payload/SaveMoney.app"
/usr/bin/ditto -c -k --keepParent "$stage_dir/Payload" "$stage_dir/SaveMoney.ipa"
/usr/bin/unzip -tq "$stage_dir/SaveMoney.ipa"
mv -f -- "$stage_dir/SaveMoney.ipa" "$out_dir/SaveMoney.ipa"
echo "Unsigned device IPA: $out_dir/SaveMoney.ipa"
echo "SideStore must sign it before installation; opening this file alone does not install it."
