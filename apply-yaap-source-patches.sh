#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

device_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
top=$(cd -- "${1:-$device_dir/../../..}" && pwd)
patch_dir="$device_dir/yaap-patches"

projects=(
    bootable/recovery
    frameworks/av
    hardware/lineage/compat
    hardware/motorola
    hardware/qcom-caf/common
    system/sepolicy
    vendor/yaap
)

# The BuildBuddy changes require the client installed by rbe_auto.
if [[ -x "$top/prebuilts/remoteexecution-client/buildbuddyfix/rewrapper" ]] &&
    [[ "${USE_RBE:-}" == true || "${USE_RBE:-}" == 1 ]]; then
    projects+=(build/make build/soong)
fi

pending=()
for project in "${projects[@]}"; do
    project_dir="$top/$project"
    prefix=$(git -C "$project_dir" rev-parse --show-prefix 2>/dev/null) || {
        printf 'Fogos YAAP setup: missing Git checkout at %s\n' "$project" >&2
        exit 1
    }
    if [[ -n "$prefix" ]]; then
        printf 'Fogos YAAP setup: %s must be a Git project root\n' "$project" >&2
        exit 1
    fi
    patch="$patch_dir/${project//\//_}.patch"
    if git -C "$project_dir" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    if ! git -C "$project_dir" apply --check "$patch"; then
        printf 'Fogos YAAP setup: %s has conflicting changes or an incompatible revision\n' \
            "$project" >&2
        exit 1
    fi
    pending+=("$project")
done

for project in "${pending[@]}"; do
    git -C "$top/$project" apply --whitespace=nowarn "$patch_dir/${project//\//_}.patch"
    printf 'Fogos YAAP setup: patched %s\n' "$project"
done
