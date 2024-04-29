#!/usr/bin/env python3
#
# Copyright (c) 2019, NVIDIA CORPORATION.  All Rights Reserved.
# Copyright (c) 2021, CTCaer.  All Rights Reserved.
#
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto.  Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.
#

import os
import signal
import gi
import nvpmodel as nvpm
import subprocess
import time
import threading
import re
import sys

gi.require_version("Gtk", "3.0")
gi.require_version('AppIndicator3', '0.1')

from gi.repository import Gtk as gtk
from gi.repository import GdkPixbuf as gdkpixbuf
from gi.repository import AppIndicator3 as appindicator
from gi.repository import GObject

INDICATOR_ID = 'nvpmodel'
INDICATORAPPS_ID = 'nvpmodel_apps'
ICON_DEFAULT = os.path.abspath('/usr/share/nvpmodel_indicator/nvpmodel-switch.svg')
ICON_SHADOW = os.path.abspath('/usr/share/nvpmodel_indicator/nvpmodel-profiles.svg')
JOYCON_MAP = os.path.abspath('/usr/share/nvpmodel_indicator/jc_map.png')

nvpmodel_helper_path = "/usr/share/nvpmodel_indicator/nvpmodel_helper.sh"

GET_COLOR_MODE = '1'
SET_COLOR_MODE = '2'
GET_COLOR_MODE_EN = '3'
GET_AUTO_PROFILES = '4'
SET_AUTO_PROFILES = '5'
GET_CHG_LIMIT_EN = '8'
GET_CHG_LIMIT_SAVED = '9'

auto_profiles = False
charging_limits = False
color_modes = False

def confirm_reboot():
    dialog = gtk.MessageDialog(None, 0, gtk.MessageType.WARNING,
        gtk.ButtonsType.OK_CANCEL, "System reboot is required to apply changes")
    dialog.set_title("WARNING")
    dialog.format_secondary_text( "Do you want to reboot NOW?")
    response = dialog.run()
    dialog.destroy()
    return response == gtk.ResponseType.OK

def set_power_mode(item, mode_id):
    if item.get_active() and mode_id != pm.cur_mode():
        success = pm.set_mode(mode_id, ['pkexec'])
        if not success and confirm_reboot():
            pm.set_mode(mode_id, ['pkexec'], force=True)
            return
        indicator.set_label(pm.get_name_by_id(pm.cur_mode()) + '  ', INDICATOR_ID)

def set_fan_mode(item, mode_id):
    if item.get_active() and mode_id != fm.cur_mode():
        success = fm.set_mode(mode_id, ['pkexec'])
        if not success and confirm_reboot():
            fm.set_mode(mode_id, ['pkexec'], force=True)
            return

def set_chg_mode(item, mode_id):
    if item.get_active() and mode_id != cm.cur_mode():
        if mode_id != "0":
            dialog = gtk.MessageDialog(None, 0, gtk.MessageType.WARNING, gtk.ButtonsType.OK,
                "Battery charging limit protection")
            dialog.set_title("WARNING")
            dialog.format_secondary_text( "This protects battery against prolonged high voltage which decreases capacity life!\n\nIt also disables charging at sleep!\n\n(The protection does not continue outside of L4T)")
            dialog.run()
            dialog.destroy()
        success = cm.set_mode(mode_id, ['pkexec'])
        if not success and confirm_reboot():
            cm.set_mode(mode_id, ['pkexec'], force=True)
            return

def set_cm_mode(item, mode_id):
    cur_mode = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE])
    if item.get_active() and mode_id != cur_mode:
        if cur_mode == 5 and mode_id >= 5:
            return
        if mode_id == 5:
            if cur_mode == 0:
                cur_mode = 4
            mode_id = cur_mode + 4;
        subprocess.call([nvpmodel_helper_path, SET_COLOR_MODE, str(mode_id)])

def do_tegrastats(_):
    cmd = "x-terminal-emulator -e pkexec tegrastats-l4t".split()
    subprocess.Popen(cmd)

def do_r2c(_):
    cmd = "pkexec r2c".split()
    subprocess.call(cmd)

def jc_map_resize(win, req):
    alloc = win.get_allocation()
    win.disconnect(win.connection_id)
    pixbuf = gdkpixbuf.Pixbuf.new_from_file(JOYCON_MAP)
    if alloc.width < 1280 and alloc.height < 720 and alloc.width != 200:
        pixbuf = pixbuf.scale_simple(alloc.width, alloc.height, gdkpixbuf.InterpType.BILINEAR)
    image = gtk.Image.new_from_pixbuf(pixbuf)
    image.show()
    win.add(image)
    win.set_title("Joy-Con Mapping")
    if alloc.width < 1280 and alloc.height < 720:
        win.maximize()
    else:
        win.unmaximize()

def do_jchelp(_):
    window = gtk.Window()
    window.show_all()
    window.connection_id = window.connect('size-allocate', jc_map_resize)
    window.maximize()

def do_auto_profiles(self):
    global auto_profiles
    if auto_profiles == self.get_active():
        return
    auto_profiles = self.get_active()
    if auto_profiles:
        subprocess.call([nvpmodel_helper_path, SET_AUTO_PROFILES, '1'])
    else:
        subprocess.call([nvpmodel_helper_path, SET_AUTO_PROFILES, '0'])

# def quit(_):
#     running.clear()
#     gtk.main_quit()

def build_menu():
    global main_menu

    menu = gtk.Menu()
    main_menu = menu

    item_pm = gtk.MenuItem('Power mode:')
    item_pm.set_sensitive(False)
    menu.append(item_pm)

    group = []
    for mode in pm.power_modes():
        label = mode.id + ': ' + mode.name
        item_mode = gtk.RadioMenuItem.new_with_label(group, label)
        group = item_mode.get_group()
        item_mode.connect('activate', set_power_mode, mode.id)
        menu.append(item_mode)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_fm = gtk.MenuItem('Fan mode:')
    item_fm.set_sensitive(False)
    menu.append(item_fm)

    fgroup = []
    for mode in fm.fan_modes():
        label = mode.id + ': ' + mode.name
        item_mode = gtk.RadioMenuItem.new_with_label(fgroup, label)
        fgroup = item_mode.get_group()
        item_mode.connect('activate', set_fan_mode, mode.id)
        menu.append(item_mode)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_set = gtk.MenuItem('Settings:')
    item_set.set_sensitive(False)
    menu.append(item_set)

    item_auto = gtk.CheckMenuItem('Automatic profiles')
    item_auto.connect('toggled', do_auto_profiles)
    menu.append(item_auto)
    auto_profiles = subprocess.call([nvpmodel_helper_path, GET_AUTO_PROFILES])
    if auto_profiles:
        item_auto.set_active(True);

    menu.show_all()
    return menu

def radio_cm_item(menu, cur_mode, grp, lbl, id):
    label = lbl
    item_mode = gtk.RadioMenuItem.new_with_label(grp, label)
    item_mode.connect('activate', set_cm_mode, id)
    if id == cur_mode:
        item_mode.set_active(True);
    menu.append(item_mode)
    cgroup = item_mode.get_group()
    return cgroup

def build_app_menu():
    global main_app_menu

    menu = gtk.Menu()
    main_app_menu = menu

    if charging_limits:
        item_fm = gtk.MenuItem('Charging Limit:')
        item_fm.set_sensitive(False)
        menu.append(item_fm)
        cgroup = []
        for mode in cm.chg_modes():
            no = eval(mode.id)
            if no is not 0:
                no += 5
            else:
                no = 100
            label = str(no) + '%: ' + mode.name
            item_mode = gtk.RadioMenuItem.new_with_label(cgroup, label)
            cgroup = item_mode.get_group()
            item_mode.connect('activate', set_chg_mode, mode.id)
            menu.append(item_mode)
        item_sep = gtk.SeparatorMenuItem()
        menu.append(item_sep)

    if color_modes:
        item_cm = gtk.MenuItem('Color Mode:')
        item_cm.set_sensitive(False)
        menu.append(item_cm)
        cur_cm_mode = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE])
        cgroup = []
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Washed Out', 1)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Basic', 2)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Natural', 3)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Vivid', 4)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Saturated', 0)
        cgroup = radio_cm_item(menu, cur_cm_mode, cgroup, 'Night Mode', 5)
        item_sep = gtk.SeparatorMenuItem()
        menu.append(item_sep)

    item_app = gtk.MenuItem('Apps:')
    item_app.set_sensitive(False)
    menu.append(item_app)

    item_tstats = gtk.MenuItem('Tegra Stats')
    item_tstats.connect('activate', do_tegrastats)
    menu.append(item_tstats)

    item_r2c = gtk.MenuItem('Reboot 2 Config')
    item_r2c.connect('activate', do_r2c)
    menu.append(item_r2c)

    item_sep = gtk.SeparatorMenuItem()
    menu.append(item_sep)

    item_jch = gtk.MenuItem('Joy-Con Mapping Help')
    item_jch.connect('activate', do_jchelp)
    menu.append(item_jch)

    # item_sep = gtk.SeparatorMenuItem()
    # menu.append(item_sep)

    # item_quit = gtk.MenuItem('Quit')
    # item_quit.connect('activate', quit)
    # menu.append(item_quit)

    menu.show_all()
    return menu

def mode_change_monitor(running):
    global main_menu
    cur_mode = pm.cur_mode()
    cur_fmode = fm.cur_mode()
    pmode_changed = False
    fmode_changed = False
    while running.is_set():
        if cur_mode != pm.cur_mode():
            pmode_changed = True
            cur_mode = pm.cur_mode()
            # Let main thread do GUI things otherwise there can be conflicts.
            GObject.idle_add(
                indicator.set_label, pm.get_name_by_id(cur_mode) + '  ', INDICATOR_ID,
                priority=GObject.PRIORITY_DEFAULT)
        if cur_fmode != fm.cur_mode():
            fmode_changed = True
            cur_fmode = fm.cur_mode()
        # Update active modes in menu
        if pmode_changed or fmode_changed:
            child = None
            fan_modes = False
            for child in main_menu.get_children():
                label = child.get_label()
                if not fan_modes and pmode_changed and label and label[0] == cur_mode:
                    pmode_changed = False
                    # Let main thread do GUI things otherwise there can be conflicts.
                    GObject.idle_add(child.set_active, True, priority=GObject.PRIORITY_DEFAULT)
                if fan_modes and fmode_changed and label and label[0] == cur_fmode:
                    fmode_changed = False
                    # Let main thread do GUI things otherwise there can be conflicts.
                    GObject.idle_add(child.set_active, True, priority=GObject.PRIORITY_DEFAULT)
                    break
                if label == 'Fan mode:':
                    fan_modes = True
        time.sleep(2)

pm = nvpm.nvpmodel()
fm = nvpm.nvfmodel()
cm = nvpm.nvcmodel()
charging_limits = subprocess.call([nvpmodel_helper_path, GET_CHG_LIMIT_EN])
color_modes = subprocess.call([nvpmodel_helper_path, GET_COLOR_MODE_EN])

# Unity panel strips underscore from indicator's label, replace '_' with
# space here so that name of power modes will be more readable.
for mode in pm.power_modes():
    mode.name = mode.name.replace('_', ' ')

for mode in fm.fan_modes():
    mode.name = mode.name.replace('_', ' ')

for mode in cm.chg_modes():
    mode.name = mode.name.replace('_', ' ')

# AppIndicator3 doesn't handle SIGINT, wire it up.
signal.signal(signal.SIGINT, signal.SIG_DFL)

pwr_mode = pm.cur_mode()
fan_mode = fm.cur_mode()
chg_mode = str(subprocess.call([nvpmodel_helper_path, GET_CHG_LIMIT_SAVED]))

indicatorApps = appindicator.Indicator.new(INDICATORAPPS_ID, ICON_DEFAULT,
    appindicator.IndicatorCategory.SYSTEM_SERVICES)
indicatorApps.set_status(appindicator.IndicatorStatus.ACTIVE)
main_app_menu = build_app_menu()
indicatorApps.set_menu(main_app_menu)

indicator = appindicator.Indicator.new(INDICATOR_ID, ICON_SHADOW,
    appindicator.IndicatorCategory.SYSTEM_SERVICES)
indicator.set_label(pm.get_name_by_id(pwr_mode) + '  ', INDICATOR_ID)
indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
main_menu = build_menu()
indicator.set_menu(main_menu)

# Set active modes in menu
child = None
fan_modes = False
chg_mode_no = eval(chg_mode)
for child in main_menu.get_children():
    label = child.get_label()
    if not fan_modes and label and label[0] == pwr_mode:
        child.set_active(True)
    if fan_modes and label and label[0] == fan_mode:
        child.set_active(True)
    if label == 'Fan mode:':
        fan_modes = True

for child in main_app_menu.get_children():
    label = child.get_label()
    if label:
        regex = re.compile("(\d+)")
        m = regex.match(label)
        if m != None:
            no = eval(m.group(1))
            if no is 100:
                no = 0
            else:
                no -= 5
            if no == chg_mode_no:
                child.set_active(True)
                break

running = threading.Event()
running.set()
threading.Thread(target=mode_change_monitor, args=[running]).start()

gtk.main()
