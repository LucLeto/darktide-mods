#!/usr/bin/env bash
set -euo pipefail

# Run against this aggregate checkout, regardless of the caller's directory.
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd -- "$repository_root"
git_root="$(cd -- "$(git rev-parse --show-toplevel)" && pwd -P)"
if [[ "$git_root" != "$repository_root" ]]; then
  echo "Error: the sync script must belong to the aggregate repository root." >&2
  exit 1
fi

temporary_directory="$(mktemp -d "$repository_root/.sync-tmp.XXXXXX")"
cleanup() {
  # Only remove the absolute temporary path created inside this checkout.
  if [[ "$temporary_directory" == "$repository_root"/.sync-tmp.* ]]; then
    rm -rf -- "$temporary_directory"
  fi
}
trap cleanup EXIT

mkdir -p -- "$temporary_directory/output/LICENSES"
sources_file="$temporary_directory/output/SOURCES.md"
cat > "$sources_file" <<'MARKDOWN'
# Sources

This file is generated automatically. Commit links identify the exact upstream revisions mirrored.

| Mod | Source repository | Branch | Commit |
| --- | --- | --- | --- |
MARKDOWN

sync_mod() {
  local display_name="$1" repository="$2" directory="$3"
  local clone_directory="$temporary_directory/source-$directory"
  local branch commit short_commit

  # Public clones need no credentials; preserve upstream file bytes on Windows.
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
    -c http.https://github.com/.extraheader= -c core.autocrlf=false \
    clone --depth 1 --single-branch --no-tags \
    "https://github.com/$repository.git" "$clone_directory"

  if [[ ! -d "$clone_directory/$directory" || -L "$clone_directory/$directory" ]]; then
    echo "Error: $repository is missing the expected mod directory $directory/." >&2
    return 1
  fi
  if [[ ! -f "$clone_directory/$directory/$directory.mod" ]]; then
    echo "Error: $repository is missing the DMF entry point $directory/$directory.mod." >&2
    return 1
  fi
  if [[ ! -f "$clone_directory/LICENSE" || ! -s "$clone_directory/LICENSE" ]]; then
    echo "Error: $repository is missing a nonempty root LICENSE file." >&2
    return 1
  fi
  if [[ -n "$(find "$clone_directory/$directory" -name .git -print -quit)" ]]; then
    echo "Error: $repository contains Git metadata inside $directory/." >&2
    return 1
  fi

  branch="$(git -C "$clone_directory" symbolic-ref --short HEAD)"
  commit="$(git -C "$clone_directory" rev-parse HEAD)"
  short_commit="$(git -C "$clone_directory" rev-parse --short=7 HEAD)"
  cp -a -- "$clone_directory/$directory" "$temporary_directory/output/$directory"
  cp -- "$clone_directory/LICENSE" "$temporary_directory/output/LICENSES/$directory.txt"
  printf '| %s | [%s](https://github.com/%s) | %s | [`%s`](https://github.com/%s/commit/%s) |\n' \
    "$display_name" "$repository" "$repository" "$branch" "$short_commit" \
    "$repository" "$commit" >> "$sources_file"
  printf 'Mirrored %s from %s (%s, %s).\n' "$directory" "$repository" "$branch" "$short_commit"
}

# Clone and validate every source before replacing any mirrored content.
# Omitting --branch follows each repository's current default branch.
sync_mod 'Radar' 'LucLeto/darktide-mods-radar' 'Radar'
sync_mod 'Icon Browser' 'LucLeto/darktide-mods-icon-browser' 'IconBrowser'
sync_mod 'Overflow Meter' 'LucLeto/darktide-mods-overflow-meter' 'OverflowMeter'
sync_mod 'Show CJK Glyphs Plus' 'LucLeto/darktide-mods-show-cjk-glyphs-plus' 'ShowCnJaKoGlyphsPlus'
sync_mod 'Perfect Thrust' 'LucLeto/darktide-mods-perfect-thrust' 'PerfectThrust'

generated_directories=(Radar IconBrowser OverflowMeter ShowCnJaKoGlyphsPlus PerfectThrust LICENSES)
for directory in "${generated_directories[@]}"; do
  if [[ -L "$repository_root/$directory" ]]; then
    echo "Error: refusing to replace symlink $directory/." >&2
    exit 1
  fi
done
if [[ -L "$repository_root/SOURCES.md" || -d "$repository_root/SOURCES.md" ]]; then
  echo "Error: SOURCES.md must be a regular file or absent." >&2
  exit 1
fi

for directory in "${generated_directories[@]}"; do
  # Fixed directory names make every removal an absolute child of this checkout.
  rm -rf -- "$repository_root/$directory"
  mv -- "$temporary_directory/output/$directory" "$repository_root/$directory"
done
mv -- "$sources_file" "$repository_root/SOURCES.md"

# Remove all temporary clones before the caller can stage or commit anything.
cleanup
trap - EXIT
