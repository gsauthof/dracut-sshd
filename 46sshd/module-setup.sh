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
    local key_prefix key_type ssh_host_key authorized_keys sshd_config
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
    elif [ -e /etc/dracut-sshd/authorized_keys ]; then
        authorized_keys=/etc/dracut-sshd/authorized_keys
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

    if [ -e /etc/dracut-sshd/wired.network ]; then
        /usr/bin/install -m 600 "/etc/dracut-sshd/wired.network" \
            "$initdir/etc/systemd/network/wired.network"
    fi

    inst_binary /usr/sbin/sshd
    inst_multiple -o /etc/sysconfig/sshd /etc/sysconfig/ssh \
            /etc/sysconfig/dracut-sshd

    # Copy ssh helper executables for OpenSSH 9.8+
    # /usr/lib/ssh          -> Arch
    # /usr/lib(64)/misc     -> Gentoo
    # /usr/libexec/openssh  -> Fedora
    # /usr/libexec/ssh      -> openSUSE
    # /usr/lib/openssh      -> Debian
    local d
    for d in /usr/lib/ssh /usr/lib64/misc /usr/lib/misc /usr/libexec/openssh /usr/libexec/ssh /usr/lib/openssh ; do
        if [ -f "$d"/sshd-session ]; then
            inst_multiple -o "$d"/{sshd-session,sftp-server,sshd-auth}
            break
        fi
    done

    # First entry for Fedora 28, second for Fedora 27
    inst_multiple -o /etc/crypto-policies/back-ends/opensshserver.config \
            /etc/crypto-policies/back-ends/openssh-server.config
    inst_simple "${moddir}/sshd.service" "$systemdsystemunitdir/sshd.service"
    if [ -e /etc/dracut-sshd/sshd_config ]; then
        sshd_config=/etc/dracut-sshd/sshd_config
    else
        sshd_config="${moddir}/sshd_config"
    fi
    inst_simple "$sshd_config" /etc/ssh/sshd_config

    { grep '^sshd:' $dracutsysrootdir/etc/passwd || echo 'sshd:x:74:74:Privilege-separated SSH:/var/empty/sshd:/sbin/nologin'; } >> "$initdir/etc/passwd"
    { grep '^sshd:' $dracutsysrootdir/etc/group  || echo 'sshd:x:74:'; } >> "$initdir/etc/group"

    # Create privilege separation directory
    # /var/empty/sshd       -> Fedora, CentOS, RHEL
    # /usr/share/empty.sshd -> Fedora >= 34
    # /var/empty            -> Arch, OpenSSH upstream
    # /var/lib/empty        -> Suse
    # /var/chroot/ssh       -> Void Linux
    local d
    for d in /var/empty/sshd /usr/share/empty.sshd /var/empty /var/lib/empty /var/chroot/ssh ; do
        if [ -d "$d" ]; then
            mkdir -p -m 0755 "$initdir$d"
        fi
    done
    # workaround for Silverblue (in general for ostree based os)
    if grep ^OSTREE_VERSION= /etc/os-release > /dev/null; then
        mkdir -p -m 0755 "$initdir/var/empty/sshd"
    fi

    systemctl -q --root "$initdir" enable sshd

    # Add command to unlock luks volumes to bash history for easier use
    echo systemd-tty-ask-password-agent >> "$initdir/root/.bash_history"
    chmod 600 "$initdir/root/.bash_history"

    # sshd requires /var/log/lastlog for tracking login information
    mkdir -p -m 0755 "$initdir/var/log"
    touch "$initdir/var/log/lastlog"

    inst_simple "${moddir}/motd" /etc/motd
    inst_simple "${moddir}/profile" /root/.profile

    return 0
}

