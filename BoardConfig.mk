# SPDX-License-Identifier: Apache-2.0

DEVICE_PATH := device/motorola/fogos

include device/motorola/sm6375-common/BoardConfigCommon.mk

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := fogos
BOARD_KERNEL_CMDLINE += androidboot.hab.product=fogos androidboot.hab.cid=50 androidboot.hab.csv=8

# Display
TARGET_SCREEN_DENSITY := 280
TARGET_RECOVERY_UI_MARGIN_HEIGHT := 90

# Partitions
BOARD_MOT_DP_GROUP_SIZE := 5901385728
BOARD_SUPER_PARTITION_SIZE := 5905580032

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/properties/system.prop
TARGET_SYSTEM_EXT_PROP += $(DEVICE_PATH)/properties/system_ext.prop
TARGET_PRODUCT_PROP += $(DEVICE_PATH)/properties/product.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/properties/vendor.prop

# Security patch levels
BOOT_SECURITY_PATCH := 2025-03-01
VENDOR_SECURITY_PATCH := 2026-09-01
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := 16
BOARD_AVB_ROLLBACK_INDEX := 16

# VINTF
DEVICE_MANIFEST_FILE += \
    $(DEVICE_PATH)/manifest_camera.xml \
    $(DEVICE_PATH)/manifest_fingerprint.xml
ODM_MANIFEST_SKUS := b d dn n
$(foreach sku,$(ODM_MANIFEST_SKUS), \
    $(eval ODM_MANIFEST_$(call to-upper,$(sku))_FILES := $(DEVICE_PATH)/sku/manifest_$(sku).xml))

include vendor/motorola/fogos/BoardConfigVendor.mk
# Sepolicy
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
