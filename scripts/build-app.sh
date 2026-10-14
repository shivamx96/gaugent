#!/usr/bin/env bash
# Builds gaugent.app into build/ from the SwiftPM package. Usage: scripts/build-app.sh [debug|release]

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
configuration=${1:-release}

case "$configuration" in
    debug|release) ;;
    *)
        echo "Usage: $0 [debug|release]" >&2
        exit 2
        ;;
esac

source_plist="$repository/Support/Info.plist"
version=${GAUGENT_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$source_plist")}
build_number=${GAUGENT_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$source_plist")}
signing_identity=${GAUGENT_SIGNING_IDENTITY:--}

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "GAUGENT_VERSION must contain three period-separated integers (for example, 1.0.0)." >&2
    exit 2
fi

declare -a architectures
if [[ -n "${GAUGENT_ARCHS:-}" ]]; then
    read -r -a architectures <<< "$GAUGENT_ARCHS"
elif [[ "$configuration" == "release" ]]; then
    architectures=(arm64 x86_64)
else
    architectures=("$(uname -m)")
fi

declare -a swift_arguments=(build --package-path "$repository" --configuration "$configuration")
for architecture in "${architectures[@]}"; do
    case "$architecture" in
        arm64|x86_64) ;;
        *)
            echo "Unsupported architecture: $architecture" >&2
            exit 2
            ;;
    esac
    swift_arguments+=(--arch "$architecture")
done

swift "${swift_arguments[@]}"
binary_directory=$(swift "${swift_arguments[@]}" --show-bin-path)

app_bundle="$repository/build/gaugent.app"
rm -rf -- "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$source_plist" "$app_bundle/Contents/Info.plist"
cp "$binary_directory/Gaugent" "$app_bundle/Contents/MacOS/Gaugent"
swift "$repository/scripts/generate-icon.swift" "$app_bundle/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_bundle/Contents/Info.plist"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$app_bundle" >/dev/null
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_bundle" >/dev/null
fi
codesign --verify --strict --verbose=2 "$app_bundle"

echo "$app_bundle"
