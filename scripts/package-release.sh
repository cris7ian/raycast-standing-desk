#!/bin/bash
set -euo pipefail

release_version="${1:?Usage: scripts/package-release.sh VERSION OUTPUT_DIRECTORY}"
output_directory="${2:?Usage: scripts/package-release.sh VERSION OUTPUT_DIRECTORY}"

if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release version must use MAJOR.MINOR.PATCH format." >&2
  exit 1
fi

mkdir -p "$output_directory"

bundle_directory="$output_directory/standing-desk-v${release_version}"
bundle_archive="$output_directory/standing-desk-v${release_version}-raycast-bundle.zip"
source_archive="$output_directory/standing-desk-v${release_version}-source.zip"
checksum_file="$output_directory/standing-desk-v${release_version}-SHA256SUMS.txt"

for release_file in "$bundle_directory" "$bundle_archive" "$source_archive" "$checksum_file"; do
  if [[ -e "$release_file" ]]; then
    echo "Release output already exists: $release_file" >&2
    exit 1
  fi
done

npx ray build --environment dist --output "$bundle_directory" --non-interactive
ditto -c -k --sequesterRsrc --keepParent "$bundle_directory" "$bundle_archive"
git archive --format=zip --prefix="standing-desk-v${release_version}/" HEAD > "$source_archive"

(
  cd "$output_directory"
  shasum -a 256 "$(basename "$bundle_archive")" "$(basename "$source_archive")" > "$(basename "$checksum_file")"
)
