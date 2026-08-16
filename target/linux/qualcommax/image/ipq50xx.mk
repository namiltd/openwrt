DTS_DIR := $(DTS_DIR)/qcom
DEVICE_VARS += BOOT_SCRIPT
# Per-device override for Build/tplink-cloud-sign (see include/image-commands.mk):
# either a PEM private key file path, or the key's own content inline as
# one line (real newlines written as literal `\n`, told apart by whether
# the value starts with "-----BEGIN") - used instead of whatever key the
# tplink-cloud-sign host tool was built with, for that specific --alg.
# Optional - unset devices keep using the host tool's own compiled-in
# default.
DEVICE_VARS += TPLINK_CLOUD_KEY_1024 TPLINK_CLOUD_KEY_2048

define Build/mstc-header
	$(eval version=$(word 1,$(1)))
	$(eval hdrlen=$(if $(word 2,$(1)),$(word 2,$(1)),0x400))
	gzip -c $@ | tail -c8 > $@.crclen
	( \
		printf "CMOC"; \
		tail -c+5 $@.crclen; head -c4 $@.crclen; \
		printf '$(call toupper,$(LINUX_KARCH)) $(VERSION_DIST) Linux-$(LINUX_VERSION)' | \
			dd bs=64 count=1 conv=sync 2>/dev/null; \
		printf "$(version)" | \
			dd bs=64 count=1 conv=sync 2>/dev/null; \
		dd if=/dev/zero bs=$$(($(hdrlen) - 0x8c)) count=1 2>/dev/null; \
		cat $@; \
	) > $@.new
	mv $@.new $@
	rm -f $@.crclen
endef

define Device/cmcc_mr3000d-ci
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := CMCC
	DEVICE_MODEL := MR3000D-CI
	DEVICE_DTS_CONFIG := config@mp03.3-m1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 59392k
	NAND_SIZE := 128m
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-cmcc_mr3000d-ci
endef
TARGET_DEVICES += cmcc_mr3000d-ci

define Device/cmcc_pz-l8
	$(call Device/FitImageLzma)
	$(call Device/UbiFit)
	DEVICE_VENDOR := CMCC
	DEVICE_MODEL := PZ-L8
	DEVICE_DTS_CONFIG := config@mp02.1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 59392k
	NAND_SIZE := 128m
endef
TARGET_DEVICES += cmcc_pz-l8

define Device/elecom_wrc-x3000gs2
	$(call Device/FitImageLzma)
	DEVICE_VENDOR := ELECOM
	DEVICE_MODEL := WRC-X3000GS2
	DEVICE_DTS_CONFIG := config@mp03.3
	SOC := ipq5018
	KERNEL_IN_UBI := 1
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 52480k
	NAND_SIZE := 128m
	IMAGES += factory.bin
	IMAGE/factory.bin := append-ubi | qsdk-ipq-factory-nand | \
		mstc-header 4.04(XZF.0)b90 | elecom-product-header WRC-X3000GS2
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-elecom_wrc-x3000gs2
endef
TARGET_DEVICES += elecom_wrc-x3000gs2

define Device/elecom_wrc-x3000gst2
	$(call Device/FitImageLzma)
	DEVICE_VENDOR := ELECOM
	DEVICE_MODEL := WRC-X3000GST2
	DEVICE_DTS_CONFIG := config@mp03.3
	SOC := ipq5018
	KERNEL_IN_UBI := 1
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 52480k
	NAND_SIZE := 128m
	IMAGES += factory.bin
	IMAGE/factory.bin := append-ubi | qsdk-ipq-factory-nand | \
		mstc-header 4.04(XZP.0)b90 | elecom-product-header WRC-X3000GST2
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-elecom_wrc-x3000gs2
endef
TARGET_DEVICES += elecom_wrc-x3000gst2

define Device/glinet_gl-b3000
	$(call Device/FitImage)
	DEVICE_VENDOR := GL.iNet
	DEVICE_MODEL := GL-B3000
	SOC := ipq5018
	KERNEL_IN_UBI := 1
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	NAND_SIZE := 128m
	DEVICE_DTS_CONFIG := config@mp03.5-c1
	SUPPORTED_DEVICES += b3000
	BOOT_SCRIPT:= glinet_gl-b3000.bootscript
	IMAGES := factory.img sysupgrade.bin
	IMAGE/factory.img := append-ubi | gl-qsdk-factory | append-metadata
	DEVICE_PACKAGES := \
		ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-glinet_gl-b3000 \
		dumpimage
endef
TARGET_DEVICES += glinet_gl-b3000

define Device/iodata_wn-dax3000gr
	$(call Device/FitImageLzma)
	DEVICE_VENDOR := I-O DATA
	DEVICE_MODEL := WN-DAX3000GR
	DEVICE_DTS_CONFIG := config@mp03.3
	SOC := ipq5018
	KERNEL_IN_UBI := 1
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	IMAGE_SIZE := 52480k
	NAND_SIZE := 128m
	IMAGES += factory.bin
	IMAGE/factory.bin := append-ubi | qsdk-ipq-factory-nand | \
		mstc-header 4.04(XZH.1)b90 0x480
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-iodata_wn-dax3000gr
endef
TARGET_DEVICES += iodata_wn-dax3000gr

define Device/linksys_ipq50xx_mx_base
	$(call Device/FitImageLzma)
	DEVICE_VENDOR := Linksys
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	KERNEL_SIZE := 8192k
	IMAGE_SIZE := 83968k
	NAND_SIZE := 256m
	SOC := ipq5018
	IMAGES += factory.bin
	IMAGE/factory.bin := append-kernel | pad-to $$$$(KERNEL_SIZE) | append-ubi | linksys-image type=$$$$(DEVICE_MODEL)
endef

define Device/linksys_mr5500
	$(call Device/linksys_ipq50xx_mx_base)
	DEVICE_MODEL := MR5500
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		ipq-wifi-linksys_mr5500 \
		kmod-usb-ledtrig-usbport
endef
TARGET_DEVICES += linksys_mr5500

define Device/linksys_mx2000
	$(call Device/linksys_ipq50xx_mx_base)
	DEVICE_MODEL := MX2000
	DEVICE_DTS_CONFIG := config@mp03.5-c1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-linksys_mx2000
endef
TARGET_DEVICES += linksys_mx2000

define Device/linksys_mx5500
	$(call Device/linksys_ipq50xx_mx_base)
	DEVICE_MODEL := MX5500
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		ipq-wifi-linksys_mx5500
endef
TARGET_DEVICES += linksys_mx5500

define Device/linksys_mx6200
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Linksys
	DEVICE_MODEL := MX6200
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	DEVICE_DTS_CONFIG := config@mp03.5-c1
	KERNEL_SIZE := 8192k
	IMAGE_SIZE := 51200k
	NAND_SIZE := 256m
	SOC := ipq5018
	IMAGE/factory.ubi := append-ubi | linksys-image type=$$$$(DEVICE_MODEL)
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-linksys_mx6200
endef
TARGET_DEVICES += linksys_mx6200

define Device/linksys_spnmx56
	$(call Device/linksys_ipq50xx_mx_base)
	DEVICE_MODEL := SPNMX56
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		ipq-wifi-linksys_spnmx56
endef
TARGET_DEVICES += linksys_spnmx56

define Device/xiaomi_ipq50xx_ax_base
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Xiaomi
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq5018
	KERNEL_SIZE := 36864k
	NAND_SIZE := 128m
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
	ARTIFACTS := initramfs-factory.ubi
	ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-uImage.itb | ubinize-kernel
endif
endef

define Device/xiaomi_ax6000
	$(call Device/xiaomi_ipq50xx_ax_base)
	DEVICE_MODEL := AX6000
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		kmod-ath10k-ct-smallbuffers \
		ath10k-firmware-qca9887-ct \
		ipq-wifi-xiaomi_ax6000
endef
TARGET_DEVICES += xiaomi_ax6000

define Device/xiaomi_redmi-ax5400
	$(call Device/xiaomi_ipq50xx_ax_base)
	DEVICE_MODEL := Redmi AX5400
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		ipq-wifi-xiaomi_redmi-ax5400
endef
TARGET_DEVICES += xiaomi_redmi-ax5400

define Device/yuncore_ax830
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Yuncore
	DEVICE_MODEL := AX830
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq5018
	DEVICE_DTS_CONFIG := config@mp03.5-c1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-yuncore_ax830
endef
TARGET_DEVICES += yuncore_ax830

define Device/yuncore_ax850
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Yuncore
	DEVICE_MODEL := AX850
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	SOC := ipq5018
	DEVICE_DTS_CONFIG := config@mp03.1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018 \
		kmod-ath11k-pci \
		ath11k-firmware-qcn9074 \
		ipq-wifi-yuncore_ax850
endef
TARGET_DEVICES += yuncore_ax850

define Device/zyxel_scr50axe
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Zyxel
	DEVICE_MODEL := SCR50AXE
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	NAND_SIZE := 256m
	DEVICE_DTS_CONFIG := config@mp03.5-c1
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-zyxel_scr50axe
endef
TARGET_DEVICES += zyxel_scr50axe

define Device/mercusys_ipq50xx_mr80x_base
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Mercusys
	DEVICE_DTS_CONFIG := config@mp02.1
	SOC := ipq5018
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	NAND_SIZE := 128m
	DEVICE_COMPAT_VERSION := 2.0
	DEVICE_COMPAT_MESSAGE := Flash layout changed to a unified rootfs. \
		Boot the matching initramfs image and reinstall from there.
	DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
		ipq-wifi-mercusys_mr80x-v2_v5 \
		kmod-ath11k \
		kmod-ath11k-ahb \
		kmod-dsa-rtl8365mb \
		kmod-leds-gpio \
		qcom-mibib \
		uboot-envtools
	# factory.itb: a "fw-type:Cloud" image (TP-Link/Mercusys's NVRAM-
	# manager firmware container - see Build/tplink-cloud-sign and
	# Build/nflash-partition-header in include/image-commands.mk for the
	# format itself), signed below with this project's own MR80X
	# research key rather than TP-Link's real one, which nobody outside
	# TP-Link has. A stock appsbl only ever trusts TP-Link's key, so
	# this image is only useful against an appsbl rebuilt in dual-key
	# mode (appsbl-toolkit, selected in .config rather than
	# DEVICE_PACKAGES here - it isn't something every MR80X build needs,
	# only one meant to also accept this key) or with the keys fully
	# replaced.
	#
	# If TP-Link ever gives the OpenWrt project its real key, none of
	# this - this key, appsbl-toolkit, the dual-key rebuild - would be
	# necessary anymore; a stock appsbl would just accept an
	# OpenWrt-signed image directly.
	TPLINK_CLOUD_KEY_2048 := -----BEGIN RSA PRIVATE KEY-----\n\
		MIIEpAIBAAKCAQEAqp5BfsHUCp7wTZYhcOI95fXE100+zHNkT5Kg/VtGDgJAsfGh\n\
		h1916qKi+sxufDHp2eNkb/XJ2Hm7wUiQvuMAFrRwlnYGZ/y/IGrV9hX7AW0j5h6i\n\
		VEZMhpqUg1xIEWDX30QNqVRs22vWxrso4fxtjlLFhI4jCrgA4pvSp+uaPNgLM01Y\n\
		zPWytTHVlX0Ma2SORky1+EwszWCsuWU/zTxNpG3dyygtNzzCwlYRWZ6wN2I3MQmz\n\
		L6N6WM6BaErJll7MDWAURFjqqe2AC13P6Q8IkWwPK9Y9Zl6VV4xEYwAmysZP2swD\n\
		VK4UHJxf6fEztxHRDkSBNCU3AjD0uef2CkvTqQIDAQABAoIBAAFbpVqOjSMhAPlj\n\
		HaTF/jdheYW7rQloTTb3bC3cDz6PDMgFy/L1gu0hSoILxMDbDlkQPuVHu+mrzV9k\n\
		VheY27AykzdVXOdwuu41f3q4EdGA9oFPQtxAG32SRyaVAlNWFZ3Gr0Om4v9rmC/o\n\
		fzKuRUp11PHhRjzgekxTcG2q+cUscTFJ7702TnrnzKQVJejiEqc4wLoVYjccKUut\n\
		bkPDdHyPqPYX5b8dFspt1G5pJJlA/i9GbJAseZS4eKYI8owbYDxzxB8ggi5D3rG3\n\
		gkJMvmjNGWmREd2tF1p59SiqxrQWeQ0Hi5npVtqlutTOpmiT42Ccz2M3sPrdvimH\n\
		O/E4IXECgYEA51lya0EGZ7zIICoJw92CcfQwK7Fn5ut6C/d0/ri6qUjx9hVxgAMA\n\
		VMBIlVw7+CbES+L+PTbcGQ4aYk4dVqEckz3VCpXvi+p++1arth28Vxu3Sa2dp/Mz\n\
		tEnr2Rw3LOoLi77bxYVdUvExY7TzhqR0RNp4UJlIN6C2hnuDl8eDTxkCgYEAvMw7\n\
		9vuAh2phdyY7Znnki/MxXKdlsNAcC8ObQYlyvBcxyYaLwEcHCytnDswWddxtXNlP\n\
		VA91W23kGPbq2PN0udiPW3KYlCtQ2LVVDLLYJHZ/2NvImQKOTsT2TKojKHII6kQD\n\
		EnV4vrjnWHRPWGzVZS95AOzIp/6peDue+ATJixECgYEAyklT2qRIzXwsILOhRjnx\n\
		TWKOnCXLDAbp+HyvN+qejFbT+rBVRfFZ4MEgtjin1xtOmGwqkaveV6oVN8/Fp3HI\n\
		Ypa2KUNg6Z5o2au3CM6HWENLyIieSbRFiWb5aiVZuVQMNGz2DYfHSjbLULtwFFLH\n\
		t0yv1wmwM7O65WwqbBRvpEECgYB7A+A2h50xnsEu73xYwyeFgMozAuehk5gSmjt5\n\
		MmPN5pcMJly8xgry3i7iV1xzI1Mm4nlr3j6reijbk1dmUQtHZLHT9hEwyiB9c3md\n\
		MpLe/09CL8K+4Al1jaSmQ11xJwxkCDiwOFaafsROwEpK5W8N5SbE0YPU4nvt2Xs1\n\
		Q3lG4QKBgQCkIf9znzPaGYn8ZHg4j6UJozlEo/5pMe3BPizjJY5HrPGxj4th07uF\n\
		ThDXGxHJ1PkdQ3Xx7OwY+KYggc/72ZcPL60Axlj/s68EzwnOvLM+bJ+y+pcXHo2t\n\
		HmGmb2nDq8VFTcUs2F2iyAlF7NyRMK6knJEwzv6HWG1EKPz2X/z6/Q==\n\
		-----END RSA PRIVATE KEY-----\n
	IMAGES += factory.itb
	IMAGE/factory.itb := append-ubi | nflash-partition-header | tplink-cloud-sign
endef

define Device/mercusys_mr80x-v2
	$(call Device/mercusys_ipq50xx_mr80x_base)
	$(call Device/FitImageLzma)
	DEVICE_MODEL := MR80X
	DEVICE_VARIANT := v2
endef
TARGET_DEVICES += mercusys_mr80x-v2

define Device/mercusys_mr80x-v5
	$(call Device/mercusys_ipq50xx_mr80x_base)
	$(call Device/FitImageLzma)
	DEVICE_MODEL := MR80X v5
endef
TARGET_DEVICES += mercusys_mr80x-v5
