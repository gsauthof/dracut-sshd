#!/bin/bash

# 2023, Warren Togami <wtogami@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# called by dracut
check() {
    require_binaries sshd || return 1
    # 0 enables by default, 255 only on request
    return 0
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    # allow NetworkManager to auto configure "Wired connection #" DHCP connections for Ethernet interfaces
    rm -f  "$initdir/usr/lib/NetworkManager/conf.d/initrd-no-auto-default.conf"

    # tell Networkmanager to run
    echo "rd.neednet" >> "${initdir}/etc/cmdline.d/50neednet.conf"
    return 0
}

