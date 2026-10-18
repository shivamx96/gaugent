#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
release_label=${1:-}
build_number=${2:-}

if [[ ! "$release_label" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    echo "Usage: scripts/release.sh <version-label> <build-number>" >&2
    echo "Example: scripts/release.sh 1.0.0-beta 1" >&2
    exit 2
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must contain a positive integer." >&2
    exit 2
fi

marketing_version=${release_label%%-*}
notary_profile=${GAUGENT_NOTARY_PROFILE:-gaugent-notary}
skip_notarization=${GAUGENT_SKIP_NOTARIZATION:-0}
allow_adhoc=${GAUGENT_ALLOW_ADHOC:-0}
signing_identity=${GAUGENT_SIGNING_IDENTITY:-}

if [[ -z "$signing_identity" ]]; then
    signing_identity=$(
        security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
            | head -n 1
    )
fi

if [[ -z "$signing_identity" ]]; then
    if [[ "$allow_adhoc" == "1" ]]; then
        signing_identity="-"
    else
        echo "No Developer ID Application identity was found." >&2
        echo "Install one or set GAUGENT_SIGNING_IDENTITY explicitly." >&2
        echo "For a local-only candidate, set GAUGENT_ALLOW_ADHOC=1 and GAUGENT_SKIP_NOTARIZATION=1." >&2
        exit 1
    fi
fi

if [[ "$signing_identity" == "-" && "$skip_notarization" != "1" ]]; then
    echo "Ad hoc builds cannot be notarized. Set GAUGENT_SKIP_NOTARIZATION=1." >&2
    exit 1
fi

artifact_suffix=""
if [[ "$skip_notarization" == "1" ]]; then
    artifact_suffix="-local"
fi

output_directory="$repository/dist"
app_bundle="$repository/build/gaugent.app"
dmg_path="$output_directory/gaugent-$release_label$artifact_suffix.dmg"
checksum_path="$dmg_path.sha256"
work_directory=$(mktemp -d /tmp/gaugent-release.XXXXXX)

cleanup() {
    if [[ "$work_directory" == /tmp/gaugent-release.* ]]; then
        rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT

mkdir -p "$output_directory"
if [[ -e "$dmg_path" || -e "$checksum_path" ]]; then
    echo "Candidate already exists; remove it explicitly before rebuilding: $dmg_path" >&2
    exit 1
fi
if [[ "$skip_notarization" != "1" ]]; then
    xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null
fi

GAUGENT_VERSION="$marketing_version" \
GAUGENT_BUILD_NUMBER="$build_number" \
GAUGENT_RELEASE_LABEL="$release_label" \
GAUGENT_ARCHS="arm64 x86_64" \
GAUGENT_SIGNING_IDENTITY="$signing_identity" \
    "$repository/scripts/build-app.sh" release

architectures=$(lipo -archs "$app_bundle/Contents/MacOS/Gaugent")
for required_architecture in arm64 x86_64; do
    if [[ " $architectures " != *" $required_architecture "* ]]; then
        echo "Release binary is missing $required_architecture." >&2
        exit 1
    fi
done

if [[ "$skip_notarization" != "1" ]]; then
    archive_path="$work_directory/gaugent-$release_label.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive_path"
    xcrun notarytool submit "$archive_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_bundle"
    xcrun stapler validate "$app_bundle"
    spctl --assess --type execute --verbose=2 "$app_bundle"
fi

staging_directory="$work_directory/disk-image"
mkdir -p "$staging_directory"
ditto "$app_bundle" "$staging_directory/gaugent.app"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
    -volname "gaugent $release_label" \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -ov \
    "$dmg_path"

if [[ "$skip_notarization" != "1" ]]; then
    codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
fi

hdiutil verify "$dmg_path"
(
    cd "$output_directory"
    shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$checksum_path")"
)

printf '\nRelease candidate created:\n%s\n%s\n' "$dmg_path" "$checksum_path"
