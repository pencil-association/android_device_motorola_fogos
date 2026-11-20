# SPDX-License-Identifier: Apache-2.0
# Sourced by build/envsetup.sh.

(
    top=$(gettop) || exit 1
    [[ -f "$top/vendor/yaap/config/common_full_phone.mk" ]] || exit 0

    bash "$top/device/motorola/fogos/apply-yaap-source-patches.sh" "$top" || exit 1

    camera="$top/vendor/motorola/camera"
    apk="$camera/proprietary/product/priv-app/MotCamera4/MotCamera4.apk"
    if [[ -f "$apk" ]] && head -c 43 "$apk" | grep -qxF 'version https://git-lfs.github.com/spec/v1'; then
        git -C "$camera" lfs pull || exit 1
    fi
)
