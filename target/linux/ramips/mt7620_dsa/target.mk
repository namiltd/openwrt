#
# Copyright (C) 2009 OpenWrt.org
#

SUBTARGET:=mt7620_dsa
BOARDNAME:=MT7620 based boards (DSA)
FEATURES+=usb ramdisk
CPU_TYPE:=24kc

DEFAULT_PACKAGES += kmod-rt2800-soc wpad-basic-mbedtls

define Target/Description
	Build firmware images for Ralink MT7620 based boards using DSA switch support.
endef
