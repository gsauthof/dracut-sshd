#!/bin/bash

# 2018, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

# called by dracut
check() {
    require_binaries sshd || return 1
    if [ -n "$dracut_sshd_tpm_pcrs" ]; then
        require_binaries openssl &&
        require_binaries tpm2_createprimary &&
        require_binaries tpm2_pcrread &&
        require_binaries tpm2_createpolicy &&
        require_binaries tpm2_create &&
        require_binaries tpm2_unseal ||
        return 1
    fi
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
    
    local tpm_tempdir
    if [ -n "$dracut_sshd_tpm_pcrs" ]; then
        tpm_tempdir=$(mktemp -d)
        ( set -e
            cd "$tpm_tempdir"
            touch key ; chmod 600 key
            openssl rand 32 > key
            tpm2_createprimary -Q -c primary.ctx
            if [ -n "$dracut_sshd_pcr_bin" ]; then
                echo "copying ${dracut_sshd_pcr_bin@Q}"
                cp "$dracut_sshd_pcr_bin" pcr.bin
            else
                echo "reading current pcrs" >&2
                tpm2_pcrread -o pcr.bin "$dracut_sshd_tpm_pcrs"
            fi
            tpm2_createpolicy -Q --policy-pcr -l "$dracut_sshd_tpm_pcrs" -f pcr.bin -L pcr.policy
            tpm2_create -Q -C primary.ctx -L pcr.policy -i key -c key.ctx
            /usr/bin/install -Dm 644 key.ctx "$initdir/etc/ssh/key.ctx"
            echo "$dracut_sshd_tpm_pcrs" > "$initdir/etc/ssh/pcrs"
        ) || {
            dfatal "Couldn't include sealed key!"
            return 1
        }
    fi 

    local found_host_key=no
    for key_type in dsa ecdsa ed25519 rsa; do
        ssh_host_key=/etc/ssh/"$key_prefix"ssh_host_"$key_type"_key
        if [ -f "$ssh_host_key" ]; then
            inst_simple "$ssh_host_key".pub /etc/ssh/ssh_host_"$key_type"_key.pub
            if [ -n "$dracut_sshd_tpm_pcrs" ]; then
                openssl aes-256-cbc -e -in "$ssh_host_key" -out "$initdir/etc/ssh/ssh_host_${key_type}_key.enc" -kfile "$tpm_tempdir/key" -iter 1
            else
                /usr/bin/install -m 600 "$ssh_host_key" \
                    "$initdir/etc/ssh/ssh_host_${key_type}_key"
            fi
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

    inst_binary /usr/sbin/sshd
    inst_multiple -o /etc/sysconfig/sshd /etc/sysconfig/ssh \
            /etc/sysconfig/dracut-sshd

    # Copy ssh helper executables for OpenSSH 9.8+
    # /usr/lib/ssh          -> Arch
    # /usr/lib(64)/misc     -> Gentoo
    # /usr/libexec/openssh  -> Fedora
    # /usr/libexec/ssh      -> openSUSE
    local d
    for d in /usr/lib/ssh /usr/lib64/misc /usr/lib/misc /usr/libexec/openssh /usr/libexec/ssh ; do
        if [ -f "$d"/sshd-session ]; then
            inst_multiple "$d"/{sshd-session,sftp-server}
            break
        fi
    done

    # First entry for Fedora 28, second for Fedora 27
    inst_multiple -o /etc/crypto-policies/back-ends/opensshserver.config \
            /etc/crypto-policies/back-ends/openssh-server.config
    inst_simple "${moddir}/sshd.service" "$systemdsystemunitdir/sshd.service"
    if [ -n "$dracut_sshd_tpm_pcrs" ]; then
        inst_binary /usr/bin/touch
        inst_binary /usr/bin/openssl
        inst_binary /usr/bin/basename
        inst_binary /usr/bin/tpm2_unseal
        inst_simple "${moddir}/unseal.sh" /usr/sbin/unseal.sh
        inst_simple "${moddir}/unseal.service" "$systemdsystemunitdir/unseal.service"
        inst_simple "${moddir}/50-unseal.conf" "$systemdsystemunitdir/sshd.service.d/50-unseal.conf"
    fi
    inst_simple "${moddir}/sshd_config" /etc/ssh/sshd_config

    { grep '^sshd:' $dracutsysrootdir/etc/passwd || echo 'sshd:x:74:74:Privilege-separated SSH:/var/empty/sshd:/sbin/nologin'; } >> "$initdir/etc/passwd"
    { grep '^sshd:' $dracutsysrootdir/etc/group  || echo 'sshd:x:74:'; } >> "$initdir/etc/group"

    # Create privilege separation directory
    # /var/empty/sshd       -> Fedora, CentOS, RHEL
    # /usr/share/empty.sshd -> Fedora >= 34
    # /var/emtpy            -> Arch, OpenSSH upstream
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

