#!/usr/bin/env bash
set -euo pipefail

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$REVISION" =~ ^[0-9a-f]{40}$ ]]
[[ "$CHECKSUM" =~ ^[0-9a-f]{64}$ ]]
git merge-base --is-ancestor "$REVISION" HEAD
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git show -s --format=%ct "$REVISION")
source_dir=$(mktemp -d)
git archive "$REVISION" | tar -x -C "$source_dir"
cd "$source_dir"
gem_path="$RUNNER_TEMP/keyed_coalescer-$VERSION.gem"
gem build keyed_coalescer.gemspec --strict --output "$gem_path"
printf '%s  %s\n' "$CHECKSUM" "$gem_path" | sha256sum --check
ruby -rrubygems/package -e '
  package = Gem::Package.new(ARGV.fetch(0))
  abort "Gem metadata does not match the requested release" unless package.verify &&
    package.spec.name == "keyed_coalescer" && package.spec.version.to_s == ARGV.fetch(1)
' "$gem_path" "$VERSION"
