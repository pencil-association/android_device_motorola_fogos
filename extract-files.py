#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
# SPDX-License-Identifier: Apache-2.0

import os

from camera.gpu_layout import fix_gpu_layout

from extract_utils.fixups_blob import blob_fixup, blob_fixups_user_type
from extract_utils.fixups_lib import lib_fixups
from extract_utils.main import ExtractUtils, ExtractUtilsModule

namespace_imports = [
    'device/motorola/fogos',
    'device/motorola/sm6375-common',
    'hardware/motorola',
    'hardware/qcom-caf/sm6375-6.1',
    'vendor/motorola/sm6375-common',
]

blob_fixups: blob_fixups_user_type = {
    (
        'vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service-fpc',
        'vendor/lib64/libacdbloader.so',
        'vendor/lib64/libgf_ca.so',
    ): blob_fixup()
        .replace_needed('libion.so', 'libion_qsecom_shim.so'),
    'vendor/lib64/camera/components/com.qti.node.gpu.so': blob_fixup()
        .call(fix_gpu_layout),
    'vendor/lib64/libmot_chi_desktop_helper.so': blob_fixup()
        .add_needed('libgui_buffer_shim_vendor.so'),
    'vendor/lib64/hw/camera.qcom.so': blob_fixup()
        .replace_needed('libsnsapi.so', 'libsnsapi-stock.so'),
    ('vendor/lib64/camera/components/com.mot.node.c2d.so', 'vendor/lib64/camera/components/com.qti.node.dewarp.so', 'vendor/lib64/camera/components/com.vidhance.node.ica.so', 'vendor/lib64/camera/components/com.vidhance.node.processing.so'): blob_fixup()
        .replace_needed('libui.so', 'libui-v34.so'),
    # The 6.1 base DT registers the charger ADC channel as chg-skin-therm,
    # so Moto's chg_therm zone never appears.
    (
        'vendor/etc/thermal-engine-fogos.conf',
        'vendor/etc/thermal-engine-fogos-camera.conf',
        'vendor/etc/thermal-engine-fogos-game-normal.conf',
        'vendor/etc/thermal-engine-fogos-game-perf.conf',
    ): blob_fixup()
        .regex_replace(r'\bchg_therm\b', 'chg-skin-therm'),
}  # fmt: skip

module = ExtractUtilsModule(
    'fogos',
    'motorola',
    blob_fixups=blob_fixups,
    lib_fixups=lib_fixups,
    namespace_imports=namespace_imports,
    add_firmware_proprietary_file=False,
    skip_main_proprietary_file=os.environ.get('SM6375_BLOB_SOURCE') == 'malmo',
)

if __name__ == '__main__':
    ExtractUtils.device_with_common(module, 'sm6375-common', module.vendor).run()
