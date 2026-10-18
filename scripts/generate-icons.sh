#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_directory=$(mktemp -d /tmp/gaugent-icons.XXXXXX)
trap 'rm -rf -- "$work_directory"' EXIT
swiftc "$repository/Sources/Gaugent/BrandArtwork.swift" "$repository/scripts/icon-generator/main.swift" -o "$work_directory/generate-icons"
"$work_directory/generate-icons" "$@"
