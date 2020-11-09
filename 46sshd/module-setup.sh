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
    return 0
}

# called by dracut
install() {
    local key_prefix key_type ssh_host_key authorized_keys
    key_prefix=
    if [ "$(find /etc/ssh -maxdepth 1 -name 'dracut_ssh_host_*_key')" ]; then
        key_prefix=dracut_
    fi
    local found_host_key=no
    for key_type in dsa ecdsa ed25519 rsa; do
        ssh_host_key=/etc/ssh/"$key_prefix"ssh_host_"$key_type"_key
        if [ -f "$ssh_host_key" ]; then
            inst_simple "$ssh_host_key".pub /etc/ssh/ssh_host_"$key_type"_key.pub
            /usr/bin/install -m 600 "$ssh_host_key" \
                    "$initdir/etc/ssh/ssh_host_${key_type}_key"
            found_host_key=yes
        fi
    done
    if [ "$found_host_key" = no ]; then
        dfatal "Didn't find any SSH host key!"
        return 1
    fi

    if [ -e /root/.ssh/dracut_authorized_keys ]; then
        authorized_keys=/root/.ssh/dracut_authorized_keys
    else
        authorized_keys=/root/.ssh/authorized_keys
    fi
    if [ ! -r "$authorized_keys" ]; then
        dfatal "No authorized_keys for root user found!"
        return 1
    fi

    mkdir -p -m 0700 "$initdir/root"
    mkdir -p -m 0700 "$initdir/root/.ssh"
    /usr/bin/install -m 600 "$authorized_keys" \
            "$initdir/root/.ssh/authorized_keys"

    inst_binary /usr/sbin/sshd
    inst_multiple -o /etc/sysconfig/sshd /etc/sysconfig/ssh \
            /etc/sysconfig/dracut-sshd

    # First entry for Fedora 28, second for Fedora 27
    inst_multiple -o /etc/crypto-policies/back-ends/opensshserver.config \
            /etc/crypto-policies/back-ends/openssh-server.config
    inst_simple "${moddir}/sshd.service" "$systemdsystemunitdir/sshd.service"


    if [ grep -Fxq "ALLOW_ROOT_PASSWORD_LOGIN=yes" /etc/sysconfig/dracut-sshd ]; then
        grep '^root:' /etc/passwd >> "$initdir/etc/passwd"
        grep '^root:' /etc/group >> "$initdir/etc/group"
        grep '^root:' /etc/shadow >> "$initdir/etc/shadow"
        if [ grep -q "^SSHD_OPTS=" /etc/sysconfig/dracut-sshd ];then
            if ! [ grep -q "^SSHD_OPTS=.*PermitRootLogin yes" /etc/sysconfig/dracut-sshd ];then
                sed -i 's/^SSHD_OPTS="[^"]*/& -o "PermitRootLogin yes"/' /etc/sysconfig/dracut-sshd
            fi
            if ! [ grep -q "^SSHD_OPTS=.*AuthenticationMethods publickey password keyboard-interactive" /etc/sysconfig/dracut-sshd ];then
                sed -i 's/^SSHD_OPTS="[^"]*/& -o "AuthenticationMethods publickey password keyboard-interactive"/' /etc/sysconfig/dracut-sshd
            fi
        else
            echo SSHD_OPTS=\' -o "PermitRootLogin yes" -o "AuthenticationMethods publickey password keyboard-interactive"\' >> /etc/sysconfig/dracut-sshd
        fi
    fi
    inst_simple "${moddir}/sshd_config" /etc/ssh/sshd_config

    grep '^sshd:' /etc/passwd >> "$initdir/etc/passwd"
    grep '^sshd:' /etc/group  >> "$initdir/etc/group"

    # Create privilege seperation directory
    # /var/empty/sshd  -> Fedora, CentOS, RHEL
    # /var/emtpy       -> Arch, OpenSSH upstream
    # /var/lib/empty   -> Suse
    # /run/sshd        -> Debian
    # /var/chroot/ssh  -> Void Linux
    local d
    for d in /var/empty/sshd /var/empty /var/lib/empty /run/sshd /var/chroot/ssh ; do
        if [ -d "$d" ]; then
            mkdir -p -m 0755 "$initdir$d"
            break
        fi
    done

    systemctl -q --root "$initdir" enable sshd

    # Add command to unlock luks volumes to bash history for easier use
    echo systemd-tty-ask-password-agent >> "$initdir/root/.bash_history"
    chmod 600 "$initdir/root/.bash_history"

    # sshd requires /var/log/lastlog for tracking login information
    mkdir -p -m 0755 "$initdir/var/log"
    touch "$initdir/var/log/lastlog"

    return 0
}
