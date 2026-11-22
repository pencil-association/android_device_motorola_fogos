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


echo "===== per-app rotation toggle ====="
(
  set -e
  cd packages/apps/Settings
  git checkout -- .    # drop leftovers from a previous run
  curl -fsSL -o /tmp/per_app_rotation_toggle.patch \
    https://raw.githubusercontent.com/FaqatZubair1/scripts/main/per_app_rotation_toggle.patch
  git apply --check /tmp/per_app_rotation_toggle.patch
  git apply /tmp/per_app_rotation_toggle.patch
  echo "per-app rotation patch applied"
) || { echo "!!! per-app rotation patch FAILED - stopping"; exit 1; }

  

echo "three finger screenshot fix"

curl -fsSL https://raw.githubusercontent.com/FaqatZubair1/scripts/main/fix_screenshot_display.sh | bash


python3 - <<'EOF'
p='vendor/voltage/build/soong/Android.bp'
s=open(p).read()
old='"if [ -n \\"$(TARGET_KERNEL_PLATFORM_TARGET)\\" ]; then " +'
new=('"if [ -n \\"$(TARGET_PREBUILT_KERNEL_HEADERS)\\" ]; then " +\n'
     '         "    mkdir -p $(genDir) && gzip -d < $(TARGET_PREBUILT_KERNEL_HEADERS) | tar -x -C $(genDir); " +\n'
     '         "elif [ -n \\"$(TARGET_KERNEL_PLATFORM_TARGET)\\" ]; then " +')
assert s.count(old)==1, s.count(old)
open(p,'w').write(s.replace(old,new))
print("patched")
EOF

if [ -d "$(gettop)/vendor/voltage" ]; then
    bash "$(gettop)/device/motorola/fogos/apply-caf-common-patches.sh" \
        "$(gettop)/hardware/qcom-caf/common" \
        || echo "WARNING: caf-common patches failed" >&2
fi

# Replace upstream LineageOS FM radio repo with my fork's fix (cnb branch)
replace_repo "https://github.com/missrais/android_vendor_qcom_opensource_fm-commonsys.git" "cnb" "vendor/qcom/opensource/commonsys/fm"

# Patch Qualcomm audio HAL:
#   1. keep the combo device (speaker + headphones) from flapping on incoming calls
#   2. mask device bitmasks with AUDIO_DEVICE_OUT_ALL, but only where the code really
#      has an `audio_devices_t devices` to mask (old HAL API)
# Safe to run repeatedly. Run from the ROM source root.
echo "Applying Qualcomm audio HAL combo device and device bitmask fixes..."
python3 - << 'EOF'
import os
import re

TAG = "[audio_hal_patch]"
MASK = "devices &= AUDIO_DEVICE_OUT_ALL;"
MASK_RE = r"devices\s*&=\s*AUDIO_DEVICE_OUT_ALL;"


def read_file(fpath):
    try:
        # surrogateescape + newline="" so odd bytes and CRLF survive the round trip
        with open(fpath, "r", encoding="utf-8", errors="surrogateescape", newline="") as f:
            return f.read()
    except OSError as e:
        print(f"{TAG} cannot read {fpath}: {e}")
        return None


def write_file(fpath, content):
    with open(fpath, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(content)


# ---------------------------------------------------------------- audio_hw.c
# Case when platform_split_snd_device fails (< 0): SM6375 / shared WCD codec backends
# cannot split speaker-and-headphones into 2 backends, so keep the combo device
# instead of falling back to d2.
COMBO_P1 = re.compile(
    r"(if\s*\(ret\s*<\s*0\)\s*\{\s*if\s*\(ret\s*!=\s*-ENOSYS\)\s*\{\s*ALOGW\([^;]+;\s*\}\s*)"
    r"ret\s*=\s*d2;\s*(goto\s+end;\s*\})"
)
# Case when backends match: keep the combo device if already on combo (case 7)
# instead of always returning d2 (case 5).
COMBO_P2 = re.compile(
    r"(if\s*\(platform_check_backends_match\(d3\[0\],\s*d3\[1\]\)\)\s*\{\s*)"
    r"ret\s*=\s*d2;\s*(goto\s+end;\s*//\s*case\s*5)"
)
COMBO_REPL = r"\1ret = (list_length(&a1) > 1 ? d1 : d2);\n            \2"

# `devices = out->devices;` (old HAL API), skipped if the mask already follows it
SELECT_DEV = re.compile(
    r"^([ \t]*)((?:\w+[ \t]+)*devices[ \t]*=[ \t]*out->devices;)"
    r"(?![ \t]*\r?\n[ \t]*" + MASK_RE + ")",
    re.M,
)


def has_combo_vars(content):
    """The combo fix only compiles if d1/d2/d3/a1 exist in derive_playback_snd_device."""
    m = re.search(r"\bderive_playback_snd_device\s*\([^)]*\)\s*\{", content)
    if not m:
        return False
    region = content[m.start(): m.end() + 8000]
    return all(re.search(p, region) for p in (r"\bd1\b", r"\bd2\b", r"\bd3\b", r"\ba1\b"))


def patch_audio_hw(fpath):
    content = read_file(fpath)
    if content is None or "derive_playback_snd_device" not in content:
        return False
    orig = content

    if has_combo_vars(content):
        content = COMBO_P1.sub(COMBO_REPL, content)
        content = COMBO_P2.sub(COMBO_REPL, content)
    else:
        print(f"{TAG} {fpath}: derive_playback_snd_device lacks d1/d2/d3/a1, skipping combo fix")

    content = SELECT_DEV.sub(r"\1\2\n\1" + MASK, content)

    if content == orig:
        print(f"{TAG} {fpath}: nothing to change")
        return False
    write_file(fpath, content)
    print(f"{TAG} patched {fpath}")
    return True


# ---------------------------------------------------------------- platform.c
# Old API:  platform_get_output_snd_device(void *platform, audio_devices_t devices)
# New API:  platform_get_output_snd_device(void *platform, struct stream_out *out, ...)
# The mask is only valid for the old API.
PLAT_SIG = r"snd_device_t\s+platform_get_output_snd_device\s*\("

PLAT_ADD = re.compile(
    r"(" + PLAT_SIG + r"[^)]*\baudio_devices_t\s+devices\b[^)]*\)\s*\{)"
    r"(?!\s*" + MASK_RE + ")"
)
# Heals files broken by the previous version of this script: new-API function
# that got the mask line inserted right after its opening brace.
PLAT_STALE = re.compile(
    r"(" + PLAT_SIG + r"(?:(?!\baudio_devices_t\s+devices\b)[^)])*\)\s*\{)"
    r"\r?\n[ \t]*" + MASK_RE + r"[ \t]*(?=\r?\n)"
)


def patch_platform(fpath):
    content = read_file(fpath)
    if content is None or "platform_get_output_snd_device" not in content:
        return False
    orig = content

    content = PLAT_STALE.sub(r"\1", content)
    content = PLAT_ADD.sub(r"\1\n    " + MASK, content)

    if content == orig:
        print(f"{TAG} {fpath}: nothing to change")
        return False
    write_file(fpath, content)
    print(f"{TAG} patched {fpath}")
    return True


# ---------------------------------------------------------------- main
patched = 0
roots = [b for b in ("hardware", "vendor") if os.path.isdir(b)]
if not roots:
    print(f"{TAG} no hardware/ or vendor/ here - run from the ROM source root")

for base in roots:
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in (".git", ".repo", "out")]
        for name in files:
            path = os.path.join(root, name)
            if name == "audio_hw.c":
                patched += patch_audio_hw(path)
            elif name in ("msm8974_platform.c", "platform.c"):
                patched += patch_platform(path)

print(f"{TAG} done, {patched} file(s) changed")
EOF
