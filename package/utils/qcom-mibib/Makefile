# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=qcom-mibib
PKG_RELEASE:=1
PKG_FLAGS:=nonshared
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/qcom-mibib
  SECTION:=utils
  CATEGORY:=Base system
  TITLE:=Qualcomm NAND MIBIB inspection and migration utility
  DEPENDS:=@(TARGET_qualcommax||TARGET_ipq40xx||TARGET_ipq806x)
endef

define Package/qcom-mibib/description
 Utility for inspecting redundant Qualcomm NAND MIBIB copies and applying
 tightly validated, board-specific partition migration profiles.
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS) -Wall -Wextra -Werror" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/qcom-mibib/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/qcom-mibib $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,qcom-mibib))
