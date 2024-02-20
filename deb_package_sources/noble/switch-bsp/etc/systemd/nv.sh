#!/bin/bash

SCRIPT_NAME=$(basename "${0}")
if [ "$(whoami)" != "root" ]; then
	echo "${SCRIPT_NAME} - ERROR: Run this script as a root user"
	exit 1
fi

# power state
if [ -e /sys/power/state ]; then
	chmod 0666 /sys/power/state
fi

# Set minimum cpu freq.
if [ -e "/proc/device-tree/compatible" ]; then
	machine="$(tr -d '\0' < /proc/device-tree/compatible)"
	if [[ "${machine}" =~ "odin" ]]; then
		machine="odin"
	elif [[ "${machine}" =~ "modin" ]]; then
		machine="modin"
	elif [[ "${machine}" =~ "vali" ]]; then
		machine="vali"
	elif [[ "${machine}" =~ "frig" ]]; then
		machine="frig"
	else
		machine="`cat /proc/device-tree/model`"
	fi

	CHIP="$(tr -d '\0' < /proc/device-tree/compatible)"
	if [[ ${CHIP} =~ "tegra210b01" ]]; then
		SOCFAMILY="tegra210b01"
	else
		SOCFAMILY="tegra210"
	fi
fi

# Remove the spawning of ondemand service
if [ -e "/etc/systemd/system/multi-user.target.wants/ondemand.service" ]; then
	rm -f "/etc/systemd/system/multi-user.target.wants/ondemand.service"
fi

# Remove the spawning of iio sensor proxy service
if [ -e "/etc/systemd/system/multi-user.target.wants/iio-sensor-proxy.service" ]; then
	rm -f "/etc/systemd/system/multi-user.target.wants/iio-sensor-proxy.service"
fi

# lp2 idle state
if [ -e /sys/module/cpuidle/parameters/power_down_in_idle ]; then
	echo "Y" > /sys/module/cpuidle/parameters/power_down_in_idle
elif [ -e /sys/module/cpuidle/parameters/lp2_in_idle ]; then
	# compatibility for prior kernels
	echo "Y" > /sys/module/cpuidle/parameters/lp2_in_idle
fi

# mmc read ahead size
if [ -e /sys/block/mmcblk0/queue/read_ahead_kb ]; then
	echo 1024 > /sys/block/mmcblk0/queue/read_ahead_kb
fi

if [ -e /sys/block/mmcblk1/queue/read_ahead_kb ]; then
	echo 1024 > /sys/block/mmcblk1/queue/read_ahead_kb
fi

CPU_INTERACTIVE_GOV=0
CPU_SCHEDUTIL_GOV=0

if [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]; \
	then
	read governors < \
		/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors

	case $governors in
		*interactive*)
			CPU_INTERACTIVE_GOV=1
		;;
	esac

	case $governors in
		*schedutil*)
			 CPU_SCHEDUTIL_GOV=1
        ;;
    esac
fi

if [[ ! -e "/sys/kernel/debug/bpmp/debug" && -e "/sys/kernel/debug/bpmp/mount" ]]; then
	cat "/sys/kernel/debug/bpmp/mount"
fi

if [ $CPU_SCHEDUTIL_GOV -eq 1 ]; then
	for scaling_governor in \
		/sys/devices/system/cpu/cpu[0-7]/cpufreq/scaling_governor; do
		echo schedutil > $scaling_governor
	done
	if [ -e /sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us ]; \
		then
		echo 2000 > \
			/sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us
	fi
	if [ -e /sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us ]; then
		echo 0 > /sys/devices/system/cpu/cpufreq/schedutil/up_rate_limit_us
	fi
	if [ -e /sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us ]; then
		echo 500 > /sys/devices/system/cpu/cpufreq/schedutil/down_rate_limit_us
	fi
	if [ -e /sys/devices/system/cpu/cpufreq/schedutil/capacity_margin ]; then
		echo 1024 > /sys/devices/system/cpu/cpufreq/schedutil/capacity_margin
	fi
elif [ $CPU_INTERACTIVE_GOV -eq 1 ]; then
	for scaling_governor in \
		/sys/devices/system/cpu/cpu[0-7]/cpufreq/scaling_governor; do
		echo interactive > $scaling_governor
	done
fi

# Ensure libglx.so is not overwritten by a distribution update of Xorg
# Alternatively, package management tools could be used to prevent updates
ARCH=`/usr/bin/dpkg --print-architecture`
if [ "x${ARCH}" = "xarm64" ]; then
	LIB_DIR="/usr/lib/aarch64-linux-gnu"
fi

# Disable lazy vfree pages
if [ -e "/proc/sys/vm/lazy_vfree_pages" ]; then
	echo 0 > "/proc/sys/vm/lazy_vfree_pages"
fi

# WAR for https://bugs.launchpad.net/ubuntu/+source/mesa/+bug/1776499
# When DISABLE_MESA_EGL="1" glvnd will not load mesa EGL library.
# When DISABLE_MESA_EGL="0" glvnd will load mesa EGL library.
# nvidia EGL library is prioritized over mesa even if DISABLE_MESA_EGL="0".
DISABLE_MESA_EGL="0"
if [ -f "/usr/share/glvnd/egl_vendor.d/50_mesa.json" ]; then
	if  [ "${DISABLE_MESA_EGL}" -eq "1" ]; then
		sed -i "s/\"library_path\" : .*/\"library_path\" : \"\"/g" \
			"/usr/share/glvnd/egl_vendor.d/50_mesa.json"
	else
		sed -i "s/\"library_path\" : .*/\"library_path\" : \"libEGL_mesa.so.0\"/g" \
			"/usr/share/glvnd/egl_vendor.d/50_mesa.json"
	fi
fi

# Add gdm in video group
grep "gdm" "/etc/group" > /dev/null
if [ $? -eq 0 ]; then
	groups "gdm" | grep "video" > /dev/null
	if [ $? -eq 1 ]; then
		usermod -a -G "video" "gdm"
	fi
fi

# Add lightdm in video group
grep "lightdm" "/etc/group" > /dev/null
if [ $? -eq 0 ]; then
	groups "lightdm" | grep "video" > /dev/null
	if [ $? -eq 1 ]; then
		usermod -a -G "video" "lightdm"
	fi
fi

if [ -e "/var/lib/lightdm" ]; then
	sudo chown lightdm:lightdm /var/lib/lightdm -R
fi

# Add sddm in video group
grep "sddm" "/etc/group" > /dev/null
if [ $? -eq 0 ]; then
	groups "sddm" | grep "video" > /dev/null
	if [ $? -eq 1 ]; then
		usermod -a -G "video" "sddm"
	fi
fi

if [ -e "/var/lib/sddm" ]; then
	sudo chown sddm:sddm /var/lib/sddm -R
fi

# Add lxdm in video group
grep "lxdm" "/etc/group" > /dev/null
if [ $? -eq 0 ]; then
	groups "lxdm" | grep "video" > /dev/null
	if [ $? -eq 1 ]; then
		usermod -a -G "video" "lxdm"
	fi
fi

if [ -e "/var/lib/lxdm" ]; then
	sudo chown lxdm:lxdm /var/lib/lxdm -R
fi

# set builtin display config
for USERDIR in /home/*
do
	if [ ! -e "$USERDIR/.config/monitors.xml" ]; then
		sudo cp /etc/skel/.config/monitors.xml $USERDIR/.config/ ;
	fi
	if [ ! -e "$USERDIR/.config/unity-monitors.xml" ]; then
		sudo cp /etc/skel/.config/unity-monitors.xml $USERDIR/.config/ ;
	fi
done

# create /etc/nvpmodel.conf symlink
conf_file=""
if [ "${SOCFAMILY}" = "tegra210" ]; then
	conf_file="/etc/nvpmodel/nvpmodel_t210.conf"
elif [ "${SOCFAMILY}" = "tegra210b01" ]; then
	conf_file="/etc/nvpmodel/nvpmodel_t210b01.conf"
fi

if [ "${conf_file}" != "" ]; then
	if [ -e "${conf_file}" ]; then
		ln -sf "${conf_file}" /etc/nvpmodel.conf
	else
		echo "${SCRIPT_NAME} - WARNING: file ${conf_file} not found!"
	fi
fi

# Set INSTALL_DOWNSTREAM_WESTON="1" to install downstream weston. This will
# overwrite weston binaries in standard weston installation path with downstream
# weston binaries which are present in ${LIB_DIR}/tegra. This is default.
#
# Set INSTALL_DOWNSTREAM_WESTON="0" to avoid overwriting weston binaries in standard
# weston installation path with downstream weston binaries which are present in
# ${LIB_DIR}/tegra.
INSTALL_DOWNSTREAM_WESTON="1"
if  [ "${INSTALL_DOWNSTREAM_WESTON}" -eq "1" ]; then
	if [ -e "${LIB_DIR}/tegra/weston/desktop-shell.so" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/desktop-shell.so" "${LIB_DIR}/weston/desktop-shell.so"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/drm-backend.so" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/drm-backend.so" "${LIB_DIR}/weston/drm-backend.so"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/fullscreen-shell.so" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/fullscreen-shell.so" "${LIB_DIR}/weston/fullscreen-shell.so"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/gl-renderer.so" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/gl-renderer.so" "${LIB_DIR}/weston/gl-renderer.so"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libweston-6.so.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libweston-6.so.0" "${LIB_DIR}/libweston-6.so.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libweston-desktop-6.so.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libweston-desktop-6.so.0" "${LIB_DIR}/libweston-desktop-6.so.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/wayland-backend.so" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/wayland-backend.so" "${LIB_DIR}/weston/wayland-backend.so"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libilmClient.so.2.2.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libilmClient.so.2.2.0" "${LIB_DIR}/libilmClient.so.2.2.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libilmCommon.so.2.2.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libilmCommon.so.2.2.0" "${LIB_DIR}/libilmCommon.so.2.2.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libilmControl.so.2.2.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libilmControl.so.2.2.0" "${LIB_DIR}/libilmControl.so.2.2.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/libilmInput.so.2.2.0" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/libilmInput.so.2.2.0" "${LIB_DIR}/libilmInput.so.2.2.0"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-desktop-shell" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-desktop-shell" "/usr/lib/weston/weston-desktop-shell"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-keyboard" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-keyboard" "/usr/lib/weston/weston-keyboard"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-screenshooter" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-screenshooter" "/usr/lib/westonweston-screenshooter"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/EGLWLInputEventExample" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/EGLWLInputEventExample" "/usr/bin/EGLWLInputEventExample"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/EGLWLMockNavigation" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/EGLWLMockNavigation" "/usr/bin/EGLWLMockNavigation"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/LayerManagerControl" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/LayerManagerControl" "/usr/bin/LayerManagerControl"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/simple-weston-client" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/simple-weston-client" "/usr/bin/simple-weston-client"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/spring-tool" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/spring-tool" "/usr/bin/spring-tool"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston" "/usr/bin/weston"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-calibrator" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-calibrator" "/usr/bin/weston-calibrator"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-clickdot" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-clickdot" "/usr/bin/weston-clickdot"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-cliptest" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-cliptest" "/usr/bin/weston-cliptest"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-content-protection" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-content-protection" "/usr/bin/weston-content-protection"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-debug" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-debug" "/usr/bin/weston-debug"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-dnd" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-dnd" "/usr/bin/weston-dnd"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-eventdemo" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-eventdemo" "/usr/bin/weston-eventdemo"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-flower" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-flower" "/usr/bin/weston-flower"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-fullscreen" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-fullscreen" "/usr/bin/weston-fullscreen"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-image" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-image" "/usr/bin/weston-image"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-info" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-info" "/usr/bin/weston-info"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-launch" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-launch" "/usr/bin/weston-launch"
		chmod "+s" "/usr/bin/weston-launch"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-multi-resource" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-multi-resource" "/usr/bin/weston-multi-resource"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-output-mode" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-output-mode" "/usr/bin/weston-output-mode"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-resizor" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-resizor" "/usr/bin/weston-resizor"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-scaler" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-scaler" "/usr/bin/weston-scaler"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-simple-egl" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-simple-egl" "/usr/bin/weston-simple-egl"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-simple-shm" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-simple-shm" "/usr/bin/weston-simple-shm"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-simple-touch" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-simple-touch" "/usr/bin/weston-simple-touch"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-smoke" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-smoke" "/usr/bin/weston-smoke"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-stacking" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-stacking" "/usr/bin/weston-stacking"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-subsurfaces" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-subsurfaces" "/usr/bin/weston-subsurfaces"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-terminal" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-terminal" "/usr/bin/weston-terminal"
	fi

	if [ -e "${LIB_DIR}/tegra/weston/weston-transformed" ]; then
		ln -sf "${LIB_DIR}/tegra/weston/weston-transformed" "/usr/bin/weston-transformed"
	fi
fi
