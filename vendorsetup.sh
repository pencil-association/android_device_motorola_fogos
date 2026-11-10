#!/bin/bash
clone_if_missing() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3
    if [ ! -d "$target_dir" ]; then
        echo "Cloning $target_dir..."
        if [ -n "$branch" ]; then
            git clone "$repo_url" -b "$branch" "$target_dir"
        else
            git clone "$repo_url" "$target_dir"
        fi
        echo "Done."
    fi
}

sync_repo() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3
    if [ ! -d "$target_dir" ]; then
        echo "Cloning $target_dir from $repo_url ($branch)..."
        if [ -n "$branch" ]; then
            git clone "$repo_url" -b "$branch" "$target_dir"
        else
            git clone "$repo_url" "$target_dir"
        fi
        echo "Done."
    else
        echo "Syncing $target_dir to latest ${branch:-HEAD}..."
        (
            cd "$target_dir" || exit
            if [ -n "$branch" ]; then
                git fetch "$repo_url" "$branch"
                git reset --hard FETCH_HEAD
            fi
        )
        echo "Done."
    fi
}

# Removes an existing repo checkout (e.g. one brought in by repo sync/manifest)
# and clones a replacement in its place.
replace_repo() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3

    echo "Removing $target_dir..."
    rm -rf "$target_dir"

    echo "Cloning $target_dir from $repo_url ($branch)..."
    git clone "$repo_url" -b "$branch" "$target_dir"
    echo "Done."
}

# Additional repos
sync_repo "https://github.com/project-moon-gazer/vendor_motorola_camera.git" "main" "vendor/motorola/camera"
if [ -d "vendor/motorola/camera" ]; then
    (cd vendor/motorola/camera && git lfs pull)
fi


#!/usr/bin/env bash
# Run from the ROM root after every `repo sync`. Safe to re-run.
set -euo pipefail

DIR="${1:-hardware/qcom-caf/common}"
URL="https://github.com/Motorola-Sedona61/hardware_qcom-caf_common.git"
BRANCH="17.0"
COMMITS=(
  08c2d1d9442deb701b99962a8422334c4c91c11b   # use exported UAPI headers when kernel is prebuilt
  bbeab6384f7ac4737ba6d177b91519a5068bd86f   # add blair (sm6375-6.1) support
  c38bb948603991a9a12f9afb53f3c5800b5fe6c0   # guard SMMU proxy for blair
)

cd "$DIR"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$(git config user.name || echo local-build)}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$(git config user.email || echo local-build@localhost)}"

git fetch -q "$URL" "$BRANCH"

for c in "${COMMITS[@]}"; do
  if git log --grep="cherry picked from commit $c" --format=%h -n1 | grep -q .; then
    echo "already applied: ${c:0:8}"
    continue
  fi
  if git cherry-pick -x "$c" >/dev/null 2>&1; then
    echo "applied:         ${c:0:8}"
  else
    git cherry-pick --abort || true
    echo "CONFLICT on ${c:0:8} - fix by hand in $DIR" >&2
    exit 1
  fi
done
