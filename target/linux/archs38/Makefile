# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2016 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=arc
CPU_TYPE:=archs
BOARD:=archs38
BOARDNAME:=Synopsys DesignWare ARC HS38
FEATURES:=source-only
SUBTARGETS:=generic

KERNEL_PATCHVER:=6.6

DEVICE_TYPE:=basic

define Target/Description
	Synopsys DesignWare boards
endef

include $(INCLUDE_DIR)/target.mk

$(eval $(call BuildTarget))
