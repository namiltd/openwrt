. /lib/functions/bootconfig.sh

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

RAMFS_COPY_BIN='dumpimage fw_printenv fw_setenv head qcom-mibib seq'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

mercusys_mr80x_set_bootenv() {
	local bootcmd
	local bootdelay
	local boot_idx

	# fw_setenv falls back to its compiled-in defaults when the OEM environment
	# is erased. Override the incompatible distro boot command explicitly.
	fw_setenv -s - <<-EOF || return 1
		bootcmd bootipq
		bootdelay 1
		tp_boot_idx 0
	EOF

	bootcmd="$(fw_printenv -n bootcmd 2>/dev/null)"
	bootdelay="$(fw_printenv -n bootdelay 2>/dev/null)"
	boot_idx="$(fw_printenv -n tp_boot_idx 2>/dev/null)"
	if [ "$bootcmd" != "bootipq" ] || [ "$bootdelay" != "1" ] ||
		[ "$boot_idx" != "0" ]; then
		echo "failed to prepare the MR80X U-Boot environment"
		return 1
	fi
}

xiaomi_initramfs_prepare() {
	# Wipe UBI if running initramfs
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	local rootfs_mtdnum="$( find_mtd_index rootfs )"
	if [ ! "$rootfs_mtdnum" ]; then
		echo "unable to find mtd partition rootfs"
		return 1
	fi

	local kern_mtdnum="$( find_mtd_index ubi_kernel )"
	if [ ! "$kern_mtdnum" ]; then
		echo "unable to find mtd partition ubi_kernel"
		return 1
	fi

	ubidetach -m "$rootfs_mtdnum"
	ubiformat /dev/mtd$rootfs_mtdnum -y

	ubidetach -m "$kern_mtdnum"
	ubiformat /dev/mtd$kern_mtdnum -y
}

mercusys_mr80x_initramfs_prepare() {
	# The stock and unified layouts overlap. Only an initramfs can safely
	# erase both stock UBI slots before activating the unified MIBIB copy.
	#
	# Shared between mr80x-v2 and mr80x-v5: confirmed the same underlying
	# hardware (same NAND partition table, RSA signing key, LED GPIOs and
	# WiFi RF calibration data - see this project's openwrt-build-tools
	# ai-memory, mr80x-v2-v5-same-hardware-evidence-20260814.md). Not yet
	# exercised on real v2 hardware; qcom-mibib's own profile check below
	# refuses to touch anything if the physical MIBIB doesn't match the
	# expected byte-for-byte layout, so a wrong assumption fails safe
	# (migration refused) instead of corrupting the device.
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	local mibib_mtdnum="$(find_mtd_index 0:mibib)"
	local rootfs_mtdnum="$(find_mtd_index rootfs)"

	if [ ! "$mibib_mtdnum" ] || [ ! "$rootfs_mtdnum" ]; then
		echo "unable to find the MR80X MIBIB or rootfs partition"
		return 1
	fi

	# Refuse unknown layouts unless both bootloader-visible MIBIB copies are
	# valid before making any destructive change to the UBI area.
	qcom-mibib probe "/dev/mtd$mibib_mtdnum" mr80x-unified ||
		return 1

	# rootfs_1 will no longer exist after the new MIBIB copy becomes active.
	# Select the primary slot and ensure an erased environment still boots via
	# the OEM bootipq command before making any destructive layout change.
	mercusys_mr80x_set_bootenv || return 1

	ubidetach -m "$rootfs_mtdnum" 2>/dev/null
	ubiformat "/dev/mtd$rootfs_mtdnum" -y || return 1

	# Replace only the older boot slot and retain the active OEM copy as a
	# fallback. The utility verifies the NAND readback before returning.
	qcom-mibib apply "/dev/mtd$mibib_mtdnum" \
		mr80x-unified --yes-really || {
		echo "failed to activate the unified MR80X MIBIB layout"
		nand_do_upgrade_failed
		return 1
	}
}

remove_oem_ubi_volume() {
	local oem_volume_name="$1"
	local oem_ubivol
	local mtdnum
	local ubidev

	mtdnum=$(find_mtd_index "$CI_UBIPART")
	if [ ! "$mtdnum" ]; then
		return
	fi

	ubidev=$(nand_find_ubi "$CI_UBIPART")
	if [ ! "$ubidev" ]; then
		ubiattach --mtdn="$mtdnum"
		ubidev=$(nand_find_ubi "$CI_UBIPART")
	fi

	if [ "$ubidev" ]; then
		oem_ubivol=$(nand_find_volume "$ubidev" "$oem_volume_name")
		[ "$oem_ubivol" ] && ubirmvol "/dev/$ubidev" --name="$oem_volume_name"
	fi
}

mercusys_mr80x_do_upgrade() {
	# This U-Boot reliably boots the primary rootfs partition. Switching
	# tp_boot_idx to the alternate rootfs_1 path makes bootipq hit a data abort.
	#
	# Keep kernel, rootfs and rootfs_data in the primary UBI. The runtime only
	# attaches this partition, so placing rootfs_data in rootfs_1 leaves a stale
	# data volume in the primary UBI and eventually makes upgrades run out of
	# PEBs while recreating rootfs.
	#
	# Shared between mr80x-v2 and mr80x-v5, see the comment on
	# mercusys_mr80x_initramfs_prepare() above.
	CI_UBIPART="rootfs"
	CI_ROOT_UBIPART="rootfs"
	CI_DATA_UBIPART="rootfs"

	mercusys_mr80x_set_bootenv || nand_do_upgrade_failed

	remove_oem_ubi_volume ubi_rootfs
	nand_do_upgrade "$1"
}

linksys_bootconfig_set_primaryboot() {
	local partname=$1
	local tempfile
	local mtdidx

	mtdidx=$(find_mtd_index "$partname")
	[ ! "$mtdidx" ] && {
		echo "cannot find mtd index for $partname"
		return 1
	}

	# No need to cleanup as files in /tmp will be removed upon reboot
	tempfile=/tmp/mtd"$mtdidx".bin
	dd if=/dev/mtd"$mtdidx" of="$tempfile" bs=1 count=336 2>/dev/null
	[ $? -ne 0 ] || [ ! -f "$tempfile" ]&& {
		echo "failed to create a temp copy of /dev/mtd$mtdidx"
		return 1
	}

	set_bootconfig_primaryboot "$tempfile" "0:HLOS" $2
	[ $? -ne 0 ] && {
		echo "failed to toggle primaryboot on 0:HLOS part"
		return 1
	}
	
	set_bootconfig_primaryboot "$tempfile" "rootfs" $2
	[ $? -ne 0 ] && {
		echo "failed to toggle primaryboot for rootfs part"
		return 1
	}

	mtd write "$tempfile" /dev/mtd"$mtdidx" 2>/dev/null
	[ $? -ne 0 ] && {
		echo "failed to write temp copy back to /dev/mtd$mtdidx"
		return 1
	}
}

linksys_bootconfig_pre_upgrade() {
	local setenv_script="/tmp/fw_env_upgrade"

	CI_UBIPART="rootfs_1"
	boot_part="$(fw_printenv -n boot_part)"
	if [ -n "$UPGRADE_OPT_USE_CURR_PART" ]; then
		CI_UBIPART="rootfs"
	else
		if [ "$boot_part" -eq "1" ]; then
			echo "boot_part 2" >> $setenv_script
			linksys_bootconfig_set_primaryboot "0:bootconfig" 1
			linksys_bootconfig_set_primaryboot "0:bootconfig1" 1
		else
			echo "boot_part 1" >> $setenv_script
			linksys_bootconfig_set_primaryboot "0:bootconfig" 0
			linksys_bootconfig_set_primaryboot "0:bootconfig1" 0
		fi
	fi

	boot_part_ready="$(fw_printenv -n boot_part_ready)"
	if [ "$boot_part_ready" -ne "3" ]; then
		echo "boot_part_ready 3" >> $setenv_script
	fi

	auto_recovery="$(fw_printenv -n auto_recovery)"
	if [ "$auto_recovery" != "yes" ]; then
		echo "auto_recovery yes" >> $setenv_script
	fi

	if [ -f "$setenv_script" ]; then
		fw_setenv -s $setenv_script || {
			echo "failed to update U-Boot environment"
			return 1
		}
	fi
}

linksys_mx_pre_upgrade() {
	local setenv_script="/tmp/fw_env_upgrade"

	CI_UBIPART="rootfs"
	boot_part="$(fw_printenv -n boot_part)"
	if [ -n "$UPGRADE_OPT_USE_CURR_PART" ]; then
		if [ "$boot_part" -eq "2" ]; then
			CI_KERNPART="alt_kernel"
			CI_UBIPART="alt_rootfs"
		fi
	else
		if [ "$boot_part" -eq "1" ]; then
			echo "boot_part 2" >> $setenv_script
			CI_KERNPART="alt_kernel"
			CI_UBIPART="alt_rootfs"
		else
			echo "boot_part 1" >> $setenv_script
		fi
	fi

	boot_part_ready="$(fw_printenv -n boot_part_ready)"
	if [ "$boot_part_ready" -ne "3" ]; then
		echo "boot_part_ready 3" >> $setenv_script
	fi

	auto_recovery="$(fw_printenv -n auto_recovery)"
	if [ "$auto_recovery" != "yes" ]; then
		echo "auto_recovery yes" >> $setenv_script
	fi

	if [ -f "$setenv_script" ]; then
		fw_setenv -s $setenv_script || {
			echo "failed to update U-Boot environment"
			return 1
		}
	fi
}

platform_check_image() {
	return 0;
}

platform_pre_upgrade() {
	case "$(board_name)" in
	mercusys,mr80x-v2|\
	mercusys,mr80x-v5)
		mercusys_mr80x_initramfs_prepare
		;;
	xiaomi,ax6000)
		xiaomi_initramfs_prepare
		;;
	esac
}

platform_do_upgrade() {
	case "$(board_name)" in
	cmcc,mr3000d-ci|\
	cmcc,pz-l8|\
	elecom,wrc-x3000gs2|\
	elecom,wrc-x3000gst2|\
	iodata,wn-dax3000gr)
		local delay

		delay=$(fw_printenv bootdelay)
		[ -z "$delay" ] || [ "$delay" -eq "0" ] && \
			fw_setenv bootdelay 3

		elecom_upgrade_prepare

		remove_oem_ubi_volume bt_fw
		remove_oem_ubi_volume ubi_rootfs
		remove_oem_ubi_volume wifi_fw
		nand_do_upgrade "$1"
		;;
	glinet,gl-b3000)
		glinet_do_upgrade "$1"
		;;
	linksys,mr5500|\
	linksys,mx2000|\
	linksys,mx5500|\
	linksys,spnmx56)
		linksys_mx_pre_upgrade "$1"
		remove_oem_ubi_volume squashfs
		nand_do_upgrade "$1"
		;;
	linksys,mx6200)
		linksys_bootconfig_pre_upgrade "$1"
		remove_oem_ubi_volume ubi_rootfs
		nand_do_upgrade "$1"
		;;
	mercusys,mr80x-v2|\
	mercusys,mr80x-v5)
		mercusys_mr80x_do_upgrade "$1"
		;;
	xiaomi,ax6000|\
	xiaomi,redmi-ax5400)
		# Make sure that UART is enabled
		fw_setenv boot_wait on
		fw_setenv uart_en 1

		# Enforce single partition.
		fw_setenv flag_boot_rootfs 0
		fw_setenv flag_last_success 0
		fw_setenv flag_boot_success 1
		fw_setenv flag_try_sys1_failed 8
		fw_setenv flag_try_sys2_failed 8

		# Kernel and rootfs are placed in 2 different UBI
		CI_KERN_UBIPART="ubi_kernel"
		CI_ROOT_UBIPART="rootfs"
		CI_DATA_UBIPART="rootfs"
		nand_do_upgrade "$1"
		;;
	yuncore,ax830|\
	yuncore,ax850|\
	zyxel,scr50axe)
		CI_UBIPART="rootfs"
		remove_oem_ubi_volume ubi_rootfs
		remove_oem_ubi_volume bt_fw
		remove_oem_ubi_volume wifi_fw
		nand_do_upgrade "$1"
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}
