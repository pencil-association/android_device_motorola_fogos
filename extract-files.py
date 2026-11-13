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
    'vendor/lib64/libarcsoft_super_night_se_raw.so': blob_fixup()
        .sig_replace(
            'e0 03 14 aa 37 3d 01 94 f3 03 00 2a 20 01 00 34',
            '94 01 00 b4 e0 03 14 aa 36 3d 01 94 09 00 00 14',
        ),
    'vendor/lib64/libmot_chi_desktop_helper.so': blob_fixup()
        .add_needed('libgui_buffer_shim_vendor.so'),
    'vendor/lib64/hw/camera.qcom.so': blob_fixup()
        .replace_needed('libsnsapi.so', 'libsnsapi-stock.so'),
    ('vendor/lib64/camera/components/com.mot.node.c2d.so', 'vendor/lib64/camera/components/com.qti.node.dewarp.so', 'vendor/lib64/camera/components/com.vidhance.node.ica.so', 'vendor/lib64/camera/components/com.vidhance.node.processing.so'): blob_fixup()
        .replace_needed('libui.so', 'libui-v34.so'),
    # The 6.1 base DT registers the charger ADC channel as chg-skin-therm,
    # so Moto's chg_therm zone never appears.
    # so Moto's chg_therm zone never appears. thermal-engine-v2 also reads
    # one offset per input sensor without bounds checks, so give the
    # three-sensor FRONT_TEMP and BACK_TEMP an offset for each sensor.
    # The v2 engine names its CPU frequency devices cpu-cluster%d, so the
    # v1-era cpu0 and cpu6 actions match nothing and both CPU rules get
    # rejected.
    (
        'vendor/etc/thermal-engine-fogos.conf',
        'vendor/etc/thermal-engine-fogos-camera.conf',
        'vendor/etc/thermal-engine-fogos-game-normal.conf',
        'vendor/etc/thermal-engine-fogos-game-perf.conf',
    ): blob_fixup()
        .regex_replace(r'\bchg_therm\b', 'chg-skin-therm')
        .regex_replace(r'(?ms)(^\[(?:FRONT|BACK)_TEMP\][^\[]*?^offsets[ \t]+)0(?=\r?$)', r'\g<1>0 0 0')
        .regex_replace(r'\bcpu0\b', 'cpu-cluster0')
        .regex_replace(r'\bcpu6\b', 'cpu-cluster1'),
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
