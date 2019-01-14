#!/bin/bash

# Make the test image a bit smaller.
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -x

PS4='+${SECONDS}s '

expendable_pkgs='
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
'

function remove_pkgs
{
    dnf -y remove $expendable_pkgs
}

function add_pkgs
{
    # XXX after next base image creation
    dnf -y install dracut-network
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
    dracut --force --regenerate-all
    rm -rf /var/lib/sss
    hardlink -v -c /usr/share/licenses
    dnf clean all
}



remove_pkgs
add_pkgs
remove_locales
enable_networkd
volatilize_logs
post_pkg_cleanup

echo done
