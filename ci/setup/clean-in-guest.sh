#!/bin/bash

# Make the test image a bit smaller.
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -x

PS4='+${SECONDS}s '


os=$(grep '^ID=' /etc/os-release | tr -d '"'  | cut -d = -f 2)


if [ $os != fedora -a $os != centos ]; then
    echo "Unknown operating system id: $os"
    exit 1
fi

if [ $os = centos ]; then
    dnf=yum
    # not all packages can be excluded via the kickstart config, cf.
    # https://unix.stackexchange.com/q/495319/1131
    expendable_pkgs=(
        '*firmware'
        'NetworkManager*'
        teamd
    )
else
    dnf=dnf
    expendable_pkgs=(
        geolite2-city
        geolite2-country
        git
        initscripts
        linux-firmware
        NetworkManager
        pigz
        pinentry
        sssd-client
        trousers
        xkeyboard-config
    )
fi

function remove_pkgs
{
    $dnf -y remove $expendable_pkgs
}

function add_pkgs
{
    # XXX after next base image creation
    $dnf -y install dracut-network
}

function remove_locales
{
    localedef --list-archive | grep  '^\(en_US\|en_US.utf8\)$' -v \
        | xargs localedef --delete-from-archive
    # with mv the bash easily coredumps inside libc's gettext ...
    cp /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
    build-locale-archive

    find /usr/share/locale -mindepth 1 -maxdepth 1 -type d -not -name 'en*' \
        -print0 | xargs -0 rm -rf
}

function enable_networkd
{
    if [ $os = centos ]; then
        return
    fi
    cat > /etc/systemd/network/20-wired.network <<EOF
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF
    systemctl enable systemd-networkd
    systemctl start  systemd-networkd
    systemctl enable systemd-resolved
    systemctl start  systemd-resolved
    ln -sf ../run/systemd/resolve/resolv.conf /etc/resolv.conf
}

function volatilize_logs
{
    rm -rf /var/log/journal
}

function post_pkg_cleanup
{
    if [ $os = centos ]; then
        # work-around slow disk device detection with CentOS 7 in non-kvm
        # environments
        systemctl disable rhel-import-state.service
        systemctl disable auditd
        systemctl disable firewalld
        sed -i 's/^#DefaultTimeoutStartSec=.*$/DefaultTimeoutStartSec=150s/' \
            /etc/systemd/system.conf
    fi
    dracut --force --regenerate-all
    rm -rf /var/lib/sss
    hardlink -v -c /usr/share/licenses
    $dnf clean all
}



remove_pkgs
add_pkgs
remove_locales
enable_networkd
volatilize_logs
post_pkg_cleanup

echo done
