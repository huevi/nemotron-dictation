#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${1:-$(uname -m)}"
case "$arch" in
  x86_64)
    asset_arch=cpu-x64
    archive_sha=82392069ea091c896dcf86fb5d86f20d107c71f6bad4b9e79a114523d98fb643
    ;;
  arm64)
    asset_arch=metal-arm64
    archive_sha=bc97b5e6253e928d1127f48f08242324317495ef8708e31db1e09b9537d1bb74
    ;;
  *)
    echo "Usage: $0 [x86_64|arm64]" >&2
    exit 2
    ;;
esac

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Install Apple's Command Line Tools with xcode-select --install, then run this script again." >&2
  exit 1
fi

version=v0.6.1
asset="parakeet-${version}-bin-macos-${asset_arch}"
archive=".cache/${asset}.tar.gz"
output="$PWD/build/$arch"
mkdir -p .cache "$output"
scratch="$(mktemp -d "$output/.build.XXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT

check_archive() {
  printf '%s  %s\n' "$archive_sha" "$1" | shasum -a 256 -c -s
}

if [[ ! -f "$archive" ]] || ! check_archive "$archive"; then
  curl --fail --location --retry 3 --connect-timeout 20 \
    "https://github.com/mudler/parakeet.cpp/releases/download/$version/$asset.tar.gz" \
    -o "$scratch/engine.tar.gz"
  check_archive "$scratch/engine.tar.gz"
  mv -f "$scratch/engine.tar.gz" "$archive"
fi

tar -xzf "$archive" -C "$scratch"
app="$scratch/Nemotron Dictation.app"
engine="$app/Contents/Resources/Engine"
mkdir -p "$app/Contents/MacOS" "$engine"
cp Info.plist "$app/Contents/"
cp "$scratch/$asset/parakeet-cli" "$scratch/$asset/LICENSE" "$engine/"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp -R licenses "$app/Contents/Resources/Third-Party-Licenses"
xcrun swiftc -target "$arch-apple-macos14.0" -O \
  NemotronDictation.swift SetupWindow.swift ModelAssets.swift main.swift \
  -o "$app/Contents/MacOS/NemotronDictation"
# The pinned upstream binaries are self-contained. Preserve their signatures
# where present by signing only the app around them.
codesign --force --sign - "$app"
codesign --verify --strict --deep "$app"

# Replace a build artifact only after the new bundle has passed verification.
destination="$output/Nemotron Dictation.app"
if [[ -e "$destination" ]]; then
  mv "$destination" "$scratch/previous.app"
fi
if ! mv "$app" "$destination"; then
  if [[ -e "$scratch/previous.app" ]]; then
    mv "$scratch/previous.app" "$destination"
  fi
  exit 1
fi
printf '\nBuilt %s\n' "$destination"
