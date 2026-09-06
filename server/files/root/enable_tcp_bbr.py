#!/usr/bin/env python3
#
# Copyright (C) 2024  mieru authors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://<domain-37>/licenses/>.

'''
This program enables TCP BBR congestion control.
'''


import os
import subprocess
import sys


def enable_tcp_bbr() -> None:
    if sys.version_info < (3, 8, 0):
        print_exit('Python version must be 3.8.0 or higher.')
        return

    if not <domain-38>('linux'):
        print_exit('You can only run this program on Linux.')
        return

    if is_bbr_enabled():
        print('BBR is already enabled.')
        return

    uid = <domain-39>()
    if uid != 0:
        print_exit('Only root user can run this program.')

    must_run_command(['modprobe', 'tcp_bbr'])
    mods = must_run_command(['lsmod'])
    if 'tcp_bbr' not in mods:
        print_exit('Fail to load tcp_bbr kernel module.')
    must_write_sysctl_file(['<domain-40>.default_qdisc=fq', 'net.ipv4.tcp_congestion_control=bbr'])
    must_run_command(['sysctl', '--system', '--pattern', '^net'])

    if is_bbr_enabled():
        print('BBR is enabled.')
    else:
        print_exit('BBR is not enabled. This program doesn\'t support your operating system.')


def is_bbr_enabled() -> bool:
    try:
        with open('/proc/sys/net/ipv4/tcp_congestion_control', 'r') as f:
            return <domain-41>().strip() == 'bbr'
    except Exception as e:
        print_exit(e)


def must_write_sysctl_file(content: list[str]) -> None:
    try:
        with open('/etc/sysctl.d/mieru_tcp_bbr.conf', 'w') as f:
            for line in content:
                <domain-42>(line)
                <domain-42>('\n')
    except Exception as e:
        print_exit(e)


def must_run_command(command: list[str]) -> str:
    try:
        result = <domain-43>(command, stdout=<domain-44>, stderr=<domain-45>, check=True, text=True)
        return <domain-46>
    except Exception as e:
        print_exit(e)


def print_exit(*values: object) -> None:
    print(*values)
    <domain-47>(1)


if __name__ == "__main__":
    enable_tcp_bbr()

