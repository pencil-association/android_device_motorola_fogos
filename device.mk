# SPDX-License-Identifier: Apache-2.0

# Soong namespaces: keep board modules ahead of inherited common modules.
PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)

# Select the board power profile before the inherited common default.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/power/powerhint.json:$(TARGET_COPY_OUT_VENDOR)/etc/powerhint.json

$(call inherit-product, device/motorola/sm6375-common/common.mk)

# Dalvik heap, as on the tested fogos builds
$(call inherit-product, frameworks/native/build/phone-xhdpi-4096-dalvik-heap.mk)

# Display
TARGET_SCREEN_DENSITY := 280
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := 280dpi
PRODUCT_AAPT_PREBUILT_DPI := xxxhdpi xxhdpi xhdpi hdpi
PRODUCT_SHIPPING_API_LEVEL := 33

# Motorola Framework
$(call inherit-product, $(LOCAL_PATH)/moto-framework/moto-framework.mk)

# Motorola Camera
$(call inherit-product, vendor/motorola/camera/camera.mk)

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.telephony.euicc.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/android.hardware.telephony.euicc.xml

# Hardware packages
PRODUCT_PACKAGES += \
    FrameworkResOverlayFogos \
    FrameworksResFogos \
    FrameworksResXT2363-8 \
    NfcOverlayFogos \
    SettingsOverlayXT2363-1 \
    SettingsOverlayXT2363-2 \
    SettingsOverlayXT2363-3 \
    SettingsOverlayXT2363-5 \
    SettingsOverlayXT2363-8 \
    SettingsProviderResFogos \
    SettingsProviderResXT2363-8 \
    SettingsResFogos \
    SystemUIOverlayFogos \
    SystemUIResFogos \
    WifiOverlayFogos \
    android.hardware.biometrics.fingerprint@2.1.vendor \
    com.motorola.hardware.biometric.fingerprint@1.0.vendor \
    libcameraservice_extension.fogos

# Camera
$(call soong_config_set,libcameraservice,ext_lib,//$(LOCAL_PATH):libcameraservice_extension.fogos)
$(call soong_config_set_bool,libcameraservice,ignore_shutter_order,true)
PRODUCT_PACKAGES += libcamera2ndk_vendor

# Audio
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/mixer_paths_blair_qrd.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_blair/mixer_paths_blair_qrd.xml \
    vendor/motorola/fogos/proprietary/vendor/etc/audio_platform_info.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_blair/audio_platform_info_intcodec.xml
$(foreach f,mixer_paths.xml audio_platform_info.xml audio_io_policy.conf, \
    $(eval PRODUCT_COPY_FILES += vendor/motorola/fogos/proprietary/vendor/etc/$(f):$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_blair/$(f)))

# Input
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/idc/uinput-fpc.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/uinput-fpc.idc \
    $(LOCAL_PATH)/configs/idc/uinput_nav.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/uinput_nav.idc \
    $(LOCAL_PATH)/configs/keylayout/uinput-fpc.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/uinput-fpc.kl \
    $(LOCAL_PATH)/configs/keylayout/uinput_nav.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/uinput_nav.kl

# Power
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/power/powerhint-blairpro.json:$(TARGET_COPY_OUT_VENDOR)/etc/powerhint-blairpro.json

# NFC: the b and d SKUs have no NFC controller.
$(foreach sku,b d, \
    $(foreach f,$(notdir $(wildcard $(LOCAL_PATH)/permissions/unavail.*.xml)), \
        $(eval PRODUCT_COPY_FILES += $(LOCAL_PATH)/permissions/$(f):$(TARGET_COPY_OUT_ODM)/etc/permissions/sku_$(sku)/$(f))))

# Touch firmware
PRODUCT_COPY_FILES += \
    vendor/motorola/fogos/proprietary/vendor/firmware/ILITEK_FW:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/lib/firmware/ILITEK_FW

# Init
$(foreach f,$(wildcard $(LOCAL_PATH)/rootdir/etc/init/hw/*.rc), \
    $(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/$(notdir $f)))
$(foreach f,$(wildcard $(LOCAL_PATH)/rootdir/bin/*.sh), \
    $(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_VENDOR)/bin/$(notdir $f)))

$(call inherit-product, vendor/motorola/fogos/fogos-vendor.mk)

DEVICE_PACKAGE_OVERLAYS += device/motorola/fogos/overlay-voltage
