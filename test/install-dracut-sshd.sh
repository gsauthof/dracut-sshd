#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


dracut_dir="$mydir"/..
guest=$(get_addr "$tag")

: ${dracut_sshd_test_nohostonly_workaround:=disable}


pushd "$dracut_dir"

$scp  -r 46sshd                 root@"$guest":/usr/lib/dracut/modules.d/


if [ "$distri" = f ]; then
    $scp  example/20-wired.network  root@"$guest":/etc/systemd/network/20-wired.network
    $scp  example/90-networkd.conf  root@"$guest":/etc/dracut.conf.d/90-networkd.conf

    $ssh root@"$guest" <<EOF
set -eux
# make sure dhcp client gets same address in early/late boot
echo -e '\n[DHCPV4]\nClientIdentifier=mac' >> /etc/systemd/network/20-wired.network
dnf -y install dracut-network

# not strictly necessary, but keeps the IP-address of the guest stable
systemctl disable NetworkManager
systemctl mask NetworkManager
systemctl enable systemd-networkd

dracut -f -v
EOF
else # RHEL, Alma, ... Linux distributions that lack networkd

    $scp  example/90-networkmanager.conf  root@"$guest":/etc/dracut.conf.d/90-networkmanager.conf

    $ssh root@"$guest" <<EOF
set -eux
dnf -y install dracut-network
case $dracut_sshd_test_nohostonly_workaround in
    disable)
        dnf -y remove dracut-config-generic
        usermod -p '*' root
        ;;
    bypass)
        grubby --args=systemd.setenv=SYSTEMD_NSS_BYPASS_SYNTHETIC=1 --update-kernel=ALL
        ;;
    rmnfs)
        dnf -y remove nfs-utils
        ;;
esac
dracut -f -v
EOF
fi
