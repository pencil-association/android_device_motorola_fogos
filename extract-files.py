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

def thermal_engine_fixup(cpu_rules=None):
    # The 6.1 base DT registers the charger ADC channel as chg-skin-therm,
    # so Moto's chg_therm zone never appears. thermal-engine-v2 also reads
    # one offset per input sensor without bounds checks, so give the
    # three-sensor FRONT_TEMP and BACK_TEMP an offset for each sensor.
    # The v2 engine names its CPU frequency devices cpu-cluster%d, so the
    # v1-era cpu0 and cpu6 actions match nothing and both CPU rules get
    # rejected.
    fixup = (
        blob_fixup()
        .regex_replace(r'\bchg_therm\b', 'chg-skin-therm')
        .regex_replace(r'(?ms)(^\[(?:FRONT|BACK)_TEMP\][^\[]*?^offsets[ \t]+)0(?=\r?$)', r'\g<1>0 0 0')
        .regex_replace(r'\bcpu0\b', 'cpu-cluster0')
        .regex_replace(r'\bcpu6\b', 'cpu-cluster1')
    )
    # Start CPU mitigation later on the BACK_TEMP skin estimate. Each rule
    # keeps its frequency steps, down to the same final floor.
    for section, (thresholds, clear) in (cpu_rules or {}).items():
        for key, values in (('thresholds', thresholds), ('thresholds_clr', clear)):
            fixup.regex_replace(
                rf'(?ms)(^\[{section}\][^\[]*?^{key}[ \t]+)[^\r\n]*',
                r'\g<1>' + ' '.join(str(value) for value in values))
    return fixup


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
    # so Moto's chg_therm zone never appears. thermal-engine-v2 also reads
    # one offset per input sensor without bounds checks, so give the
    # three-sensor FRONT_TEMP and BACK_TEMP an offset for each sensor.
    # The v2 engine names its CPU frequency devices cpu-cluster%d, so the
    # v1-era cpu0 and cpu6 actions match nothing and both CPU rules get
    # rejected.
    'vendor/etc/thermal-engine-fogos.conf': thermal_engine_fixup({
        'MON-MSM-CPU0': ((44000, 45500, 46500, 47500, 48500), (43000, 44500, 45500, 46500, 47500)),
        'MON-MSM-CPU6': ((44000, 45500, 47000, 48500, 49000), (43000, 44500, 46000, 47500, 48500)),
    }),
    'vendor/etc/thermal-engine-fogos-camera.conf': thermal_engine_fixup({
        'MON-MSM-CPU0': ((40000, 42000, 44000, 46000, 48000), (38000, 40000, 42000, 44000, 46000)),
        'MON-MSM-CPU6': ((40000, 42000, 44000, 46000, 48000), (38000, 40000, 42000, 44000, 46000)),
    }),
    'vendor/etc/thermal-engine-fogos-game-normal.conf': thermal_engine_fixup({
        'MON-MSM-CPU0': ((43000, 45000, 46500, 47500, 48500), (42000, 44000, 45500, 46500, 47500)),
        'MON-MSM-CPU6': ((43000, 45000, 46500, 48000), (42000, 44000, 45500, 47000)),
    }),
    'vendor/etc/thermal-engine-fogos-game-perf.conf': thermal_engine_fixup(),
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
