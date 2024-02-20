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
import sys
import re
import subprocess
import fileinput

conf_paths = [
    "/odm/etc/nvpmodel.conf",
    "/vendor/etc/nvpmodel.conf",
    "/etc/nvpmodel.conf",
]

charging_limits_paths = [
    "/etc/nvpmodel/nvpmodel_charging.conf",
]

status_paths = "/var/lib/nvpmodel/status"
charging_status_paths = "/var/lib/nvpmodel/charging_status"
nvpmodel_helper_path = "/usr/share/nvpmodel_indicator/nvpmodel_helper.sh"

GET_CHG_LIMIT = '6'
SET_CHG_LIMIT = '7'

def parse_preset(conf):
    # < PM_CONFIG DEFAULT=? >
    regex = re.compile("<\s+PM_CONFIG\s+DEFAULT=(\d+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            return m.group(1)

def parse_fan_preset(conf):
    # < FAN_CONFIG DEFAULT=? >
    regex = re.compile("<\s+FAN_CONFIG\s+DEFAULT=(\w+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            return m.group(1)

class nvpmodel_setting(object):
    def __init__(self, name, attr, val):
        self.name = name
        self.attr = attr
        self.value = val

    def __repr__(self):
        return str([self.name, self.attr, self.value])

def parse_settings(vals):
    settings = []
    for v in vals:
        name, attr, val = v
        settings.append(nvpmodel_setting(name, attr, val))
    return settings

class power_mode(object):
    def __init__(self, mode_id, name, vals):
        self.id = mode_id
        self.name = name
        self.settings = parse_settings(vals)

    def __repr__(self):
        return str([self.id, self.name, self.vals])

def parse_power_mode(conf):
    modes = []
    # < POWER_MODEL ID=? NAME=? >
    regex = re.compile("<\s+POWER_MODEL\s+ID=(\d+)\s+NAME=([A-Za-z0-9_.()|]+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            vals = []
            # < PARAM_NAME ARG_NAME ARG_VAL >
            for arg in conf[conf.index(line)+1:]:
                if arg[0] != '<':
                    vals.append(arg.split())
                else:
                    break
            modes.append(power_mode(m.group(1), m.group(2), vals))
    return modes

class fan_mode(object):
    def __init__(self, mode_id, name):
        self.id = mode_id
        self.name = name

    def __repr__(self):
        return str([self.id, self.name])

class chg_mode(object):
    def __init__(self, mode_id, name):
        self.id = mode_id
        self.name = name

    def __repr__(self):
        return str([self.id, self.name])

def parse_fan_mode(conf):
    modes = []
    # < FAN_MODEL ID=? NAME=? DEV1_COEF=? DEV2_COEF=? >
    regex = re.compile("<\s+FAN_MODEL\s+ID=(\d+)\s+NAME=(\w+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            modes.append(fan_mode(m.group(1), m.group(2)))
    return modes

def parse_chg_mode(conf):
    modes = []
    # < CHG_MODEL LIMIT=? NAME=? >
    modes.append(chg_mode("0", "No Limit"))
    regex = re.compile("<\s+CHG_MODEL\s+LIMIT=(\d+)\s+NAME=(\w+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            modes.append(chg_mode(m.group(1), m.group(2)))
    return modes

class param_arg(object):
    def __init__(self, arg):
        self.name, self.path = arg.split()

    def __repr__(self):
        return str([self.name, self.path])

def parse_args(args):
    param_args = []
    for a in args:
        param_args.append(param_arg(a))
    return param_args

class nvpmodel_param(object):
    def __init__(self, p_type, name, args):
        self.name = name
        self.type = p_type
        self.args = parse_args(args)

    def __repr__(self):
        return str([self.name, self.type, self.args])

def parse_params(conf):
    params = []
    # < PARAM TYPE=? NAME=? >
    regex = re.compile("<\s+PARAM\s+TYPE=(\w+)\s+NAME=(\w+)\s+>")
    for line in conf:
        m = regex.match(line)
        if m != None:
            args = []
            for arg in conf[conf.index(line)+1:]:
                if arg[0] != '<':
                    args.append(arg)
                else:
                    break
            params.append(nvpmodel_param(m.group(1), m.group(2), args))
    return params

class nvpmodel_conf(object):
    def __init__(self, conf):
        self.preset = parse_preset(conf)
        self.power_modes = parse_power_mode(conf)
        self.params = parse_params(conf)

class nvfmodel_conf(object):
    def __init__(self, conf):
        self.preset = parse_fan_preset(conf)
        self.fan_modes = parse_fan_mode(conf)

class nvcmodel_conf(object):
    def __init__(self, conf):
        self.preset = "0"
        self.chg_modes = parse_chg_mode(conf)

def import_conf(paths):
    conf = []
    conf_file = None

    for p in paths:
        if os.path.isfile(p):
            f = open(p)
            conf_file = p
            for line in f:
                line = line.strip()
                if line == '' or line[0] == '#':
                    continue
                conf.append(line)
            f.close()
            break

    return conf_file, conf

class nvpmodel(object):
    """nvpmodel backend class

    This class aims to aid nvpmodel frontend development by providing
    helper functions on top of nvpmodel command line utility and also
    expose nvpmodel configuration as a more accessible structure.
    """

    def __init__(self):
        self.conf_path, self.raw_conf = import_conf(conf_paths)
        self.conf = nvpmodel_conf(self.raw_conf)

    def preset_mode(self):
        """get preset default power mode specified in configuration file."""

        return self.conf.preset

    def power_modes(self):
        """return a list of all power modes defined in configuration file."""

        return self.conf.power_modes

    def cur_mode(self):
        """return current power mode."""

        if os.path.isfile(status_paths):
            mode = ""
            regex = re.compile("pmode:(\w+).*")
            f = open(status_paths)
            for line in f:
                m = regex.match(line)
                if m != None:
                    mode = str(int(m.group(1)))
            f.close()
            return mode

    def get_name_by_id(self, mode_id):
        """get human-readable power mode name by its id."""

        for m in self.conf.power_modes:
            if mode_id == m.id:
                return m.name
        return ""

    def get_mode_param(self, mode_id, param_name):
        """get power mode parameter given power mode id and its name."""

        for m in self.conf.power_modes:
            if mode_id == m.id:
                for s in m.settings:
                    if s.name == param_name:
                        return s.value

    def set_mode(self, mode, cmd=[], force=False):
        """change current power mode.

        passing `force=True` is required for switching to modes that needs
        reboot to take effect.
        """

        cmd.extend(['nvpmodel', '-m', mode])
        cur_tpc = self.get_mode_param(self.cur_mode(), 'TPC_POWER_GATING')
        new_tpc = self.get_mode_param(mode, 'TPC_POWER_GATING')
        if cur_tpc != new_tpc:
            if not force:
                return False
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
            p.communicate(bytes('YES', 'utf-8'))
            p.wait()
            rc = p.returncode
        else:
            rc = subprocess.call(cmd)
        return rc == 0

    def machine_name(self):
        """get model name of the machine."""

        try:
            with open("/proc/device-tree/model") as f:
                return f.read()
        except IOError:
                return "unknown"

    def cpu_count(self):
        """get number of total CPU cores present to the system."""

        try:
            with open("/sys/devices/system/cpu/present") as f:
                for line in f:
                    return int(line.split('-')[1]) + 1
        except IOError:
                return 1

    def get_param_type_by_name(self, name):
        """look up power mode parameter type (CLOCK or FILE) by its name."""

        param_type = None
        for p in self.conf.params:
            if p.name == name:
                param_type = p.type
                break
        return param_type

    def save_power_mode_setting(self, mode_id, setting):
        """save given power mode setting back to configuration file."""

        mode_name = self.get_name_by_id(mode_id)
        skip = True
        found = False
        f = fileinput.FileInput(self.conf_path, inplace=True, backup='.bak')
        for line in f:
            if mode_name not in line and skip:
                print(line.strip())
                continue
            else:
                skip = False
            if setting.attr not in line:
                print(line.strip())
                continue
            replace = line.split()
            replace[2] = setting.value
            print(" ".join(replace))
            found = True
            skip = True
        return found

class nvfmodel(object):
    """nvfmodel backend class

    This class aims to aid nvfmodel frontend development by providing
    helper functions on top of nvfmodel command line utility and also
    expose nvfmodel configuration as a more accessible structure.
    """

    def __init__(self):
        self.conf_path, self.raw_conf = import_conf(conf_paths)
        self.conf = nvfmodel_conf(self.raw_conf)

    def preset_mode(self):
        """get preset default fan mode specified in configuration file."""

        return self.conf.preset

    def fan_modes(self):
        """return a list of all fan modes defined in configuration file."""

        return self.conf.fan_modes

    def cur_mode(self):
        """return current fan mode."""

        if os.path.isfile(status_paths):
            mode = ""
            regex = re.compile(".*fmode:(\w+).*")
            f = open(status_paths)
            for line in f:
                m = regex.match(line)
                if m != None:
                    for n in self.conf.fan_modes:
                        if m.group(1) == n.name:
                            mode = n.id
            f.close()
            return mode

    def get_name_by_id(self, mode_id):
        """get human-readable fan mode name by its id."""

        for m in self.conf.fan_modes:
            if mode_id == m.id:
                return m.name
        return ""

    def set_mode(self, mode, cmd=[], force=False):
        """change current fan mode."""

        mode_name = self.get_name_by_id(mode)
        cmd.extend(['nvpmodel', '-d', mode_name])
        rc = subprocess.call(cmd)
        return rc == 0

class nvcmodel(object):
    """nvcmodel backend class

    This class aims to aid nvcmodel frontend development by providing
    helper functions on top of nvcfmodel command line utility and also
    expose nvcmodel configuration as a more accessible structure.
    """

    def __init__(self):
        self.conf_path, self.raw_conf = import_conf(charging_limits_paths)
        self.conf = nvcmodel_conf(self.raw_conf)

    def preset_mode(self):
        """get preset default charging mode specified in configuration file."""

        return self.conf.preset

    def chg_modes(self):
        """return a list of all charging modes defined in configuration file."""

        return self.conf.chg_modes

    def cur_mode(self):
        """return current charging mode."""

        mode = str(subprocess.call([nvpmodel_helper_path, GET_CHG_LIMIT]))
        return mode

    def get_name_by_id(self, mode_id):
        """get human-readable charging mode name by its id."""

        for m in self.conf.chg_modes:
            if mode_id == m.id:
                return m.name
        return ""

    def set_mode(self, mode, cmd=[], force=False):
        """change current charging mode."""
        rc = subprocess.call([nvpmodel_helper_path, SET_CHG_LIMIT, mode])
        return True

if __name__ == '__main__':
    nvpm = nvpmodel()
    nvfm = nvfmodel()

    print("nvpmodel:")
    print("\tmachine %s" % nvpm.machine_name())
    print("\tcpu count %s" % nvpm.cpu_count())
    print("\tconf path %s" % nvpm.conf_path)
    print("\tparams")
    for p in nvpm.conf.params:
        print("\t\t%s (%s)" % (p.name, p.type))
        for a in p.args:
            print("\t\t%s" % a)

    print("\n\tpreset fan mode %s %s" % (nvfm.preset_mode(), nvfm.get_name_by_id(nvfm.preset_mode())))
    print("\tcurrent fan mode %s %s" % (nvfm.cur_mode(), nvfm.get_name_by_id(nvfm.cur_mode())))
    print("\tfan mode settings:")
    for mode in nvfm.fan_modes():
        print("\t\t %s" % mode.name)

    print("\tpreset power mode %s %s" % (nvpm.preset_mode(), nvpm.get_name_by_id(nvpm.preset_mode())))
    print("\tcurrent power mode %s %s" % (nvpm.cur_mode(), nvpm.get_name_by_id(nvpm.cur_mode())))
    print("\tpower mode settings:")
    for mode in nvpm.power_modes():
        print("\t\t %s" % mode.name)
        for setting in mode.settings:
            print("\t\t%s (%s)" % (setting, nvpm.get_param_type_by_name(setting.name)))

    if os.geteuid() != 0:
        sys.exit(0)

    print("\ttry saving new settings to power mode %s (%s)" % (mode.id, mode.name))
    setting = mode.settings[1]
    print("\t\told: %s" % setting)
    setting.value = "TEST_WRITE"
    print("\t\tnew: %s" % setting)
    if nvpm.save_power_mode_setting(mode.id, setting):
        print("\tchecking modified conf file..")
        subprocess.call(["diff", nvpm.conf_path + ".bak", nvpm.conf_path])
        subprocess.call(["mv", nvpm.conf_path + ".bak", nvpm.conf_path])
    else:
        print("\t\tsaving new setting FAILED")
        sys.exit(1)

    orig_mode = nvpm.cur_mode()
    for mode in nvpm.power_modes():
        print("\ttry switching to power mode %s.. " % mode.id)
        cur_tpc = nvpm.get_mode_param(nvpm.cur_mode(), 'TPC_POWER_GATING')
        new_tpc = nvpm.get_mode_param(mode.id, 'TPC_POWER_GATING')
        if cur_tpc != new_tpc:
            print("\tSKIPPED. Operation requires reboot.")
            continue

        success = nvpm.set_mode(mode.id)
        if success:
            print("\tSUCCESS")
        else:
            print("\tFAILED")
            break

    orig_fmode = nvfm.cur_mode()
    for mode in nvfm.fan_modes():
        print("\ttry switching to fan mode %s.. " % mode.name)

        success = nvfm.set_mode(mode.id)
        if success:
            print("\tSUCCESS")
        else:
            print("\tFAILED")
            break

    print("\nSelf test completed, restoring to original power/fan mode.")
    nvpm.set_mode(orig_mode)
    nvfm.set_mode(orig_fmode)
    sys.exit(int(success == False))
