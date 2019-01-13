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
        # it's more lightweight than using the ifcfg dracut module
        # and it isn't enabled, by default
        echo systemd-networkd
    fi
    # we don't need to depend on network because ifcfg already depends on it
    # and ifcfg is enabled, by default, in CentOS 7/Fedora 27/28
    # echo network
}

# called by dracut
install() {
    local key_prefix key_type ssh_host_key authorized_keys
    key_prefix=
    if [ "$(find /etc/ssh -maxdepth 1 -name 'dracut_ssh_host_*_key')" ]; then
        key_prefix=dracut_
    fi
    for key_type in dsa ecdsa ed25519 rsa; do
        ssh_host_key=/etc/ssh/"$key_prefix"ssh_host_"$key_type"_key
        if [ -f "$ssh_host_key" ]; then
            inst_simple "$ssh_host_key".pub /etc/ssh/ssh_host_"$key_type"_key.pub
            /usr/bin/install -m 600 "$ssh_host_key" \
                    "$initdir/etc/ssh/ssh_host_${key_type}_key"
        fi
    done

    authorized_keys=/root/.ssh/authorized_keys

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

    # Add command to unlock luks volumes to bash history for easier use
    echo "systemd-tty-ask-password-agent" >> "$initdir/root/.bash_history"
    chmod 600 "$initdir/root/.bash_history"

    return 0
}

