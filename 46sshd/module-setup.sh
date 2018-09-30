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
    inst_multiple /usr/sbin/sshd \
        /etc/sysconfig/sshd
    # First entry for Fedora 28, second for Fedora 27
    inst_multiple -o /etc/crypto-policies/back-ends/opensshserver.config \
            /etc/crypto-policies/back-ends/openssh-server.config
    inst_simple "${moddir}/sshd.service" "$systemdsystemunitdir/sshd.service"
    inst_simple "${moddir}/sshd_config" /etc/ssh/sshd_config

    local ssh_host_keys ssh_host_key authorized_keys
    # check for specific keys to include in dracut initrd
    local old_ng=$(shopt -p nullglob)
    shopt -s nullglob
    ssh_host_keys=(/etc/ssh/dracut_*key)
    if [ ${#ssh_host_keys[*]} = 0 ]; then
        echo "No dracut specific ssh keys found. Using host ssh keys."
        ssh_host_keys=(/etc/ssh/ssh_host_*key)
    fi
    $old_ng
    for ssh_host_key in "${ssh_host_keys[@]}"; do
        inst_simple "$ssh_host_key".pub "$ssh_host_key".pub
        /usr/bin/install -m 600 "$ssh_host_key" \
                "${initdir}$ssh_host_key"
        echo "HostKey $ssh_host_key" >> "$initdir/etc/ssh/sshd_config"
    done

    authorized_keys=/root/.ssh/authorized_keys
    mkdir -p -m 700 "$initdir/root/.ssh"
    chmod 700 "$initdir/root"
    /usr/bin/install -m 600 "$authorized_keys" \
            "$initdir/root/.ssh/authorized_keys"

    grep '^sshd:' /etc/passwd >> "$initdir/etc/passwd"
    grep '^sshd:' /etc/group  >> "$initdir/etc/group"

    mkdir -p "$initdir/var/empty/sshd"

    systemctl --root "$initdir" enable sshd

    # as of Fedora 28, the systemd-networkd dracut module doesn't
    # include those files
    inst_multiple -o /etc/systemd/network/*

    return 0
}

