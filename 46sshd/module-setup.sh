#!/bin/bash

# 2018, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

# called by dracut
check() {
    require_binaries sshd || return 1
    # 0 enables by default, 255 only on request
    return 0
}

# called by dracut
depends() {
    # e.g. CentOS 7 doesn't has systemd-networkd
    if [ -f /usr/lib/systemd/systemd-networkd ]; then
        echo systemd-networkd
    fi
    echo network
}

# called by dracut
install() {
    local ssh_host_key authorized_keys
    if [ -f /etc/ssh/dracut_ssh_host_ed25519_key ]; then
        ssh_host_key=/etc/ssh/dracut_ssh_host_ed25519_key
    else
        ssh_host_key=/etc/ssh/ssh_host_ed25519_key
    fi
    authorized_keys=/root/.ssh/authorized_keys

    inst_simple "$ssh_host_key".pub /etc/ssh/ssh_host_ed25519_key.pub
    /usr/bin/install -m 600 "$ssh_host_key" \
            "$initdir/etc/ssh/ssh_host_ed25519_key"

    mkdir -p -m 700 "$initdir/root/.ssh"
    chmod 700 "$initdir/root"
    /usr/bin/install -m 600 "$authorized_keys" \
            "$initdir/root/.ssh/authorized_keys"

    inst_multiple /usr/sbin/sshd \
        /etc/sysconfig/sshd
    # First entry for Fedora 28, second for Fedora 27
    inst_multiple -o /etc/crypto-policies/back-ends/opensshserver.config \
            /etc/crypto-policies/back-ends/openssh-server.config
    inst_simple "${moddir}/sshd.service" "$systemdsystemunitdir/sshd.service"
    inst_simple "${moddir}/sshd_config" /etc/ssh/sshd_config

    grep '^sshd:' /etc/passwd >> "$initdir/etc/passwd"
    grep '^sshd:' /etc/group  >> "$initdir/etc/group"

    mkdir -p "$initdir/var/empty/sshd"

    systemctl --root "$initdir" enable sshd

    # as of Fedora 28, the systemd-networkd dracut module doesn't
    # include those files
    inst_multiple -o /etc/systemd/network/*

    return 0
}

