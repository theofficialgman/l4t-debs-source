#!/bin/bash
# Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
#
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto.  Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.

# This script runs on target to check if need to update QSPI partitions for Nano
# If the running system version match the bootloader debian package,
# then check the VER in QSPI, if the VER is less then running system version,
# install the package to update QSPI.

BOOT_CTRL_CONF="/etc/nv_boot_control.conf"
T210REF_UPDATER="/usr/sbin/l4t_payload_updater_t210"
PACKAGE_DIR="/opt/nvidia/l4t-packages/bootloader"
PACKAGE_NAME="nvidia-l4t-bootloader"

# When create image, user may flash device with symlik board
# config name or orignal name, so the nv_boot_control.conf
# may have different board name informaton.
# Unify it to "jetson-*"
update_boot_ctrl_conf() {
	tnspec=$( awk '/TNSPEC/ {print $2}' "${BOOT_CTRL_CONF}" )

	if [[ "${tnspec}" == *"p3448-0000-emmc"* ]]; then
		# "jetson-nano-emmc" for "p3448-0000-emmc"
		sed -i 's/p3448-0000-emmc/jetson-nano-emmc/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p3448-0000-sd"* ]]; then
		# "jetson-nano-qspi-sd" for "p3448-0000-sd"
		sed -i 's/p3448-0000-sd/jetson-nano-qspi-sd/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p3448-0000"* ]]; then
		# "jetson-nano-qspi" for "p3448-0000"
		sed -i 's/p3448-0000/jetson-nano-qspi/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2371-2180-devkit"* ]]; then
		# "jetson-tx1" for "p2371-2180-devkit"
		sed -i 's/p2371-2180-devkit/jetson-tx1/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2771-0000-devkit"* ]]; then
		# "jetson-tx2" for "p2771-0000-devkit"
		sed -i 's/p2771-0000-devkit/jetson-tx2/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2771-3489-ucm1"* ]]; then
		# "jetson-tx2i" for "p2771-3489-ucm1"
		sed -i 's/p2771-3489-ucm1/jetson-tx2i/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2771-0000-0888"* ]]; then
		# "jetson-tx2-4GB" for "p2771-0000-0888"
		sed -i 's/p2771-0000-0888/jetson-tx2-4GB/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2771-0000-as-0888"* ]]; then
		# "jetson-tx2-as-4GB" for "p2771-0000-as-0888"
		sed -i 's/p2771-0000-as-0888/jetson-tx2-as-4GB/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2972-0000-devkit-maxn"* ]]; then
		# "jetson-xavier-maxn" for "p2972-0000-devkit-maxn"
		sed -i 's/p2972-0000-devkit-maxn/jetson-xavier-maxn/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2972-0000-devkit-slvs-ec"* ]]; then
		# "jetson-xavier-slvs-ec" for "p2972-0000-devkit-slvs-ec"
		sed -i 's/p2972-0000-devkit-slvs-ec/jetson-xavier-slvs-ec/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2972-0000-devkit"* ]]; then
		# "jetson-xavier" for "p2972-0000-devkit"
		sed -i 's/p2972-0000-devkit/jetson-xavier/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2972-0006-devkit"* ]]; then
		# "jetson-xavier-8gb" for "p2972-0006-devkit"
		sed -i 's/p2972-0006-devkit/jetson-xavier-8gb/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2972-as-galen-8gb"* ]]; then
		# "jetson-xavier-as-8gb" for "p2972-as-galen-8gb"
		sed -i 's/p2972-as-galen-8gb/jetson-xavier-as-8gb/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	elif [[ "${tnspec}" == *"p2822+p2888-0001-as-p3668-0001"* ]]; then
		# "jetson-xavier-as-xavier-nx" for "p2822+p2888-0001-as-p3668-0001"
		sed -i 's/p2822+p2888-0001-as-p3668-0001/jetson-xavier-as-xavier-nx/g' "${rootfs_dir}/etc/nv_boot_control.conf";
	fi
}

# check qspi version, if need update it.
# return:  0: needs update; 1: doesn't need update.
t210ref_update_qspi_check () {
	# 1. get installed bootloader package's version
	# sample: ii  nvidia-l4t-bootloader  32.2.0-20190514154120  arm64  NVIDIA Bootloader Package
	# installed_deb_ver=32.2.0-20190514154120
	installed_deb_ver="$(dpkg -l | grep "${PACKAGE_NAME}" | awk '/'${PACKAGE_NAME}'/ {print $3}')"
	if [ -z "${installed_deb_ver}" ]; then
		return 1
	fi

	# 2. get main deb_version
	deb_version="$(echo "${installed_deb_ver}" | cut -d "-" -f 1)"

	# 3. use deb_version as sys_version
	# sample: sys_rel=32, sys_maj_rev=2, sys_min_rev=0
	sys_rel="$(echo "${deb_version}" | cut -d "." -f 1)"
	sys_maj_rev="$(echo "${deb_version}" | cut -d "." -f 2)"
	sys_min_rev="$(echo "${deb_version}" | cut -d "." -f 3)"

	# read VER partition to get QSPI version
	if [ -x "${T210REF_UPDATER}" ]; then
		ver_info="$(${T210REF_UPDATER} -v)"
		if [ "${ver_info}" == "NV1" ]; then
			qspi_rel=31
			qspi_maj_rev=0
			qspi_min_rev=0
		else
			rel_number="$(echo "${ver_info}" | awk '/#/ {print $2}')"
			qspi_rel="$(echo "${rel_number}" | sed 's/R//')"

			# get revision=2.0
			revision=$(echo "${ver_info}" | awk '/#/ {print $5}')
			revision="$(echo "${revision}" | sed 's/,//')"

			# get maj_rev=2, min_rev=0
			qspi_maj_rev="$(echo "${revision}" | cut -d "." -f 1)"
			qspi_min_rev="$(echo "${revision}" | cut -d "." -f 2)"
		fi
	else
		return 1
	fi

	if (( "${sys_rel}" > "${qspi_rel}" )); then
		# sys_rel > qspi_rel
		# need to update QSPI
		return 0
	elif (( "${sys_rel}" == "${qspi_rel}" )); then
		if (( "${sys_maj_rev}" > "${qspi_maj_rev}" )); then
			# sys_rel == qspi_rel
			# sys_maj_rev > qspi_maj_rev
			# need to update QSPI
			return 0
		elif (( "${sys_maj_rev}" == "${qspi_maj_rev}" )); then
			if (( "${sys_min_rev}" >= "${qspi_min_rev}" )); then
				# sys_rel == qspi_rel
				# sys_maj_rev == qspi_maj_rev
				# sys_min_rev >= qspi_min_rev
				# need to update QSPI
				return 0
			else
				return 1
			fi
		else
			return 1
		fi
	else
		return 1
	fi
}

t210ref_update_qspi () {
	tnspec=$( awk '/TNSPEC/ {print $2}' "${BOOT_CTRL_CONF}" )
	if [[ "${tnspec}" == *"jetson-nano-qspi-sd"* ]]; then
		if t210ref_update_qspi_check; then
			dpkg-reconfigure "${PACKAGE_NAME}"
		fi
	fi
}

if [ ! -r "${BOOT_CTRL_CONF}" ]; then
	echo "Error. Cannot open ${BOOT_CTRL_CONF} for reading."
	echo "Cannot install package. Exiting..."
	exit 1
fi

chipid=$( awk '/TEGRA_CHIPID/ {print $2}' "${BOOT_CTRL_CONF}" )

update_boot_ctrl_conf

case "${chipid}" in
	0x21)
		t210ref_update_qspi
		;;
esac
