#!/bin/bash

if   [ "$1" -eq 1 ]; then # Get panel color mode.
     exit $(cat /sys/devices/50000000.host1x/tegradc.0/panel_color_mode)
elif [ "$1" -eq 2 ]; then # Set panel color mode.
     if [ ! -e "/sys/devices/50000000.host1x/tegradc.0/panel_color_mode" ]; then exit 1; fi
     echo $2 > /sys/devices/50000000.host1x/tegradc.0/panel_color_mode
     echo $2 > /var/lib/nvpmodel/color_mode
elif [ "$1" -eq 3 ]; then # Get panel color mode supported.
     if [ -e "/sys/devices/50000000.host1x/tegradc.0/panel_color_mode" ]; then exit 1; else exit 0; fi
elif [ "$1" -eq 4 ]; then # Get auto profile.
     if [ ! -e "/var/lib/nvpmodel/auto_profiles" ]; then exit 0; fi
     if grep -q 0 "/var/lib/nvpmodel/auto_profiles"; then exit 0; else exit 1; fi
elif [ "$1" -eq 5 ]; then # Set auto profile.
     echo $2 > /var/lib/nvpmodel/auto_profiles
elif [ "$1" -eq 6 ]; then # Get current charging limit.
     exit $(cat /sys/class/power_supply/usb/charge_control_limit)
elif [ "$1" -eq 7 ]; then # Set charging limit.
     echo $2 > /sys/class/power_supply/usb/charge_control_limit
     echo $2 > /var/lib/nvpmodel/charging_status
elif [ "$1" -eq 8 ]; then # Get charging limit supported.
     if [ -e "/sys/class/power_supply/usb/charge_control_limit" ]; then exit 1; else exit 0; fi
elif [ "$1" -eq 9 ]; then # Get saved charging limit.
     if [ ! -e "/var/lib/nvpmodel/charging_status" ]; then exit 0; fi
     exit $(cat /var/lib/nvpmodel/charging_status)
fi
