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
                git fetch "$repo_url" "$branch" && git reset --hard FETCH_HEAD
            fi
        )
        echo "Done."
    fi
}

# Keep the existing checkout until the replacement is ready.
replace_repo() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3
    local staging_dir
    staging_dir=$(mktemp -d "${target_dir}.setup.XXXXXX") || return 1

    echo "Preparing $target_dir from $repo_url ($branch)..."
    if ! git clone --branch "$branch" "$repo_url" "$staging_dir/replacement"; then
        rm -rf -- "$staging_dir"
        return 1
    fi
    if [ -e "$target_dir" ] || [ -L "$target_dir" ]; then
        mv -- "$target_dir" "$staging_dir/previous" || return 1
    fi
    if ! mv -T -- "$staging_dir/replacement" "$target_dir"; then
        if [ -e "$staging_dir/previous" ] || [ -L "$staging_dir/previous" ]; then
            mv -T -- "$staging_dir/previous" "$target_dir" || return 1
        fi
        rm -rf -- "$staging_dir"
        return 1
    fi
    rm -rf -- "$staging_dir"
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
replace_repo "https://github.com/missrais/android_vendor_qcom_opensource_fm-commonsys.git" "cnb" \
    "vendor/qcom/opensource/commonsys/fm" || echo "WARNING: FM radio checkout replacement failed" >&2

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
HELPERS = """
static inline bool is_headphones_snd_dev(snd_device_t d) {
    return (d == SND_DEVICE_OUT_HEADPHONES ||
            d == SND_DEVICE_OUT_HEADPHONES_44_1 ||
            d == SND_DEVICE_OUT_HEADPHONES_HIFI_FILTER);
}
static inline bool is_speaker_snd_dev(snd_device_t d) {
    return (d == SND_DEVICE_OUT_SPEAKER ||
            d == SND_DEVICE_OUT_SPEAKER_REVERSE);
}
"""
DERIVE_DECL = r"snd_device_t[ \t]+derive_playback_snd_device\b"
HELPERS_ANCHOR = re.compile(r"^((?:static\s+)?" + DERIVE_DECL + r")", re.M)
STALE_STATIC = re.compile(
    r"^static[ \t]*\n(" + re.escape(HELPERS.lstrip("\n") + "\n") + r")(?=" + DERIVE_DECL + r")",
    re.M,
)

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
COMBO_REPL = r"\1ret = (list_length(&a1) > 1 ? d1 : (list_length(&a2) > 1 ? d2 : d2));\n            \2"

# Disjoint case: when two concurrent streams on shared codec backend request
# speaker and headphones (e.g. ringtone on speaker while headphones connected/media playing),
# resolve to combo device instead of infinitely flapping back and forth.
DISJOINT_P = re.compile(
    r"(if\s*\(platform_check_backends_match\(d1,\s*d2\)\)\s*\{\s*)"
    r"ret\s*=\s*d2;\s*(goto\s+end;\s*//\s*case\s*2,\s*4)"
)
DISJOINT_REPL = r"""\1if ((is_speaker_snd_dev(d1) && is_headphones_snd_dev(d2)) ||
                (is_headphones_snd_dev(d1) && is_speaker_snd_dev(d2)) ||
                (d1 == SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES && (is_speaker_snd_dev(d2) || is_headphones_snd_dev(d2))) ||
                (d2 == SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES && (is_speaker_snd_dev(d1) || is_headphones_snd_dev(d1)))) {
                ret = SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES;
            } else if ((d1 == SND_DEVICE_OUT_SPEAKER_SAFE && is_headphones_snd_dev(d2)) ||
                       (is_headphones_snd_dev(d1) && d2 == SND_DEVICE_OUT_SPEAKER_SAFE) ||
                       (d1 == SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES && (d2 == SND_DEVICE_OUT_SPEAKER_SAFE || is_headphones_snd_dev(d2))) ||
                       (d2 == SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES && (d1 == SND_DEVICE_OUT_SPEAKER_SAFE || is_headphones_snd_dev(d1)))) {
                ret = SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES;
            } else {
                ret = d2;
            }
            \2"""

# In select_devices(): when determining out_snd_device for a playback stream,
# if another active playback stream is already playing on combo or complementary device,
# promote out_snd_device to combo so the active combo route is not torn down.
SELECT_OUT_SND = re.compile(
    r"(out_snd_device\s*=\s*platform_get_output_snd_device\(adev->platform,\s*"
    r"usecase->stream\.out,\s*"
    r"usecase->type\);)"
)
SELECT_OUT_REPL = r"""\1
                /* [fogos_combo_fix] */
                {
                    struct listnode *node_iter;
                    list_for_each(node_iter, &adev->usecase_list) {
                        struct audio_usecase *uc_act = node_to_item(node_iter, struct audio_usecase, list);
                        if (uc_act != usecase && uc_act->type == PCM_PLAYBACK) {
                            if (uc_act->out_snd_device == SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES ||
                                (is_speaker_snd_dev(uc_act->out_snd_device) && is_headphones_snd_dev(out_snd_device)) ||
                                (is_headphones_snd_dev(uc_act->out_snd_device) && is_speaker_snd_dev(out_snd_device))) {
                                out_snd_device = SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES;
                                break;
                            } else if (uc_act->out_snd_device == SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES ||
                                       (uc_act->out_snd_device == SND_DEVICE_OUT_SPEAKER_SAFE && is_headphones_snd_dev(out_snd_device)) ||
                                       (is_headphones_snd_dev(uc_act->out_snd_device) && out_snd_device == SND_DEVICE_OUT_SPEAKER_SAFE)) {
                                out_snd_device = SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES;
                                break;
                            }
                        }
                    }
                }"""

# In stop_output_stream(): when a combo stream stops, trigger select_devices() on any
# remaining playback usecase on the combo route so it restores cleanly to its requested device.
STOP_OUT = re.compile(
    r"(list_remove\(&uc_info->list\);\s*"
    r"out->started\s*=\s*0;)"
)
STOP_OUT_REPL = r"""\1
    /* [fogos_stop_fix] */
    if (uc_info->out_snd_device == SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES ||
        uc_info->out_snd_device == SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES) {
        struct listnode *node_iter;
        list_for_each(node_iter, &adev->usecase_list) {
            struct audio_usecase *uc_rem = node_to_item(node_iter, struct audio_usecase, list);
            if (uc_rem->type == PCM_PLAYBACK &&
                (uc_rem->out_snd_device == SND_DEVICE_OUT_SPEAKER_AND_HEADPHONES ||
                 uc_rem->out_snd_device == SND_DEVICE_OUT_SPEAKER_SAFE_AND_HEADPHONES)) {
                select_devices(adev, uc_rem->id);
            }
        }
    }"""

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
        content = STALE_STATIC.sub(r"\1static ", content)
        if not re.search(r"\bis_headphones_snd_dev\b", content):
            content = HELPERS_ANCHOR.sub(HELPERS + r"\n\1", content, count=1)
        content = COMBO_P1.sub(COMBO_REPL, content)
        content = COMBO_P2.sub(COMBO_REPL, content)
        content = DISJOINT_P.sub(DISJOINT_REPL, content)
        if "/* [fogos_combo_fix] */" not in content:
            m = re.search(r"if\s*\(\s*usecase->type\s*==\s*PCM_PLAYBACK\s*\)", content)
            if m:
                subm = SELECT_OUT_SND.search(content, m.start())
                if subm:
                    content = content[:subm.start()] + SELECT_OUT_SND.sub(SELECT_OUT_REPL, subm.group(0)) + content[subm.end():]
        if "/* [fogos_stop_fix] */" not in content:
            content = STOP_OUT.sub(STOP_OUT_REPL, content, count=1)
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
