#
# MT7620A (DSA) Profiles
#

include ./common-sercomm.mk
include ./common-tp-link.mk

define Device/mercusys_ac12g-v1-8m-dsa
  $(Device/tplink-v2)
  SOC := mt7620a
  IMAGE_SIZE := 7808k
  TPLINK_FLASHLAYOUT := 8Mmtk
  TPLINK_HWID := 0x04da857c
  TPLINK_HWREV := 0x0c000600
  TPLINK_HWREVADD := 0x04000000
  KERNEL := kernel-bin | append-dtb | lzma -d22
  KERNEL_INITRAMFS := kernel-bin | append-dtb | lzma -d22 | tplink-v2-header -e
  IMAGES += tftp-recovery.bin
  IMAGE/tftp-recovery.bin := pad-extra 128k | $$(IMAGE/factory.bin)
  DEVICE_VENDOR := Mercusys
  DEVICE_MODEL := AC12G
  DEVICE_VARIANT := v1 (8M) (DSA)
  DEVICE_PACKAGES := kmod-mt76x2 kmod-dsa-rtl8365mb kmod-fixed-phy kmod-ledtrig-network
endef
TARGET_DEVICES += mercusys_ac12g-v1-8m-dsa
