# SPDX-License-Identifier: Apache-2.0

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/halcyon_fogos.mk \
    $(LOCAL_DIR)/lineage_fogos.mk \
    $(LOCAL_DIR)/voltage_fogos.mk

COMMON_LUNCH_CHOICES := \
    halcyon_fogos-cp2a-userdebug \
    lineage_fogos-cp2a-userdebug  \
    voltage_fogos-cp2a-userdebug
