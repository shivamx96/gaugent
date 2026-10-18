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

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "GAUGENT_BUILD_NUMBER must be a positive integer." >&2
    exit 2
fi
release_label=${GAUGENT_RELEASE_LABEL:-$version}

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

/usr/libexec/PlistBuddy -c "Add :GaugentReleaseLabel string $release_label" "$app_bundle/Contents/Info.plist"

appcast_url=${GAUGENT_APPCAST_URL:-}
public_key=${GAUGENT_SPARKLE_PUBLIC_KEY:-}
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $appcast_url" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$app_bundle/Contents/Info.plist"

# Sparkle ships as a binary XCFramework. SwiftPM leaves it beside the executable, but a
# bundle needs it in Contents/Frameworks, and the binary needs an rpath that points there.
sparkle_framework=$(
    find "$repository/.build/artifacts" \
        -type d \
        -path "*macos-arm64_x86_64/Sparkle.framework" \
        -print -quit
)

if [[ -z "$sparkle_framework" ]]; then
    echo "Sparkle.framework was not found. Run 'swift package resolve' first." >&2
    exit 1
fi

rm -rf -- "$app_bundle/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$app_bundle/Contents/MacOS/Gaugent" | grep 'path @executable_path/../Frameworks ' >/dev/null; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_bundle/Contents/MacOS/Gaugent"
fi

# Nested code must be signed before the code that contains it, innermost first.
# --deep is not a substitute: it cannot apply the hardened runtime per nested bundle.
declare -a nested_code=(
    "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    "Contents/Frameworks/Sparkle.framework/Versions/B"
)

sign() {
    local target=$1
    if [[ "$signing_identity" == "-" ]]; then
        codesign --force --sign - "$target" >/dev/null
    else
        codesign \
            --force \
            --options runtime \
            --timestamp \
            --sign "$signing_identity" \
            "$target" >/dev/null
    fi
}

for relative_path in "${nested_code[@]}"; do
    if [[ -e "$app_bundle/$relative_path" ]]; then
        sign "$app_bundle/$relative_path"
    fi
done

sign "$app_bundle"

codesign --verify --deep --strict --verbose=2 "$app_bundle"

echo "$app_bundle"
