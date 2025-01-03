#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


dracut_dir="$mydir"/..
guest=$(get_addr "$tag")


pushd "$dracut_dir"

$scp  -r 46sshd                 root@"$guest":/usr/lib/dracut/modules.d/


if [ "$distri" = f ]; then
    $scp  example/20-wired.network  root@"$guest":/etc/systemd/network/20-wired.network
    $scp  example/90-networkd.conf  root@"$guest":/etc/dracut.conf.d/90-networkd.conf
    $scp  example/50-tpm.conf  root@"$guest":/etc/dracut.conf.d/50-tpm.conf

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

    # NB: RHEL/Alma images already have dracut-network pre-installed

    $ssh root@"$guest" <<EOF
set -eux
function f {
    sed '/^GRUB_CMDLINE_LINUX\(_DEFAULT\|\)="[^"]*'"\$1"'[^"]*"/!s/^GRUB_CMDLINE_LINUX\(_DEFAULT\|\)="[^"]*/& '"\$1"'/' \
        /etc/default/grub -i
}
f 'rd.neednet=1 ip=dhcp'

# kernelopts are used on RHEL8, nullop on RHEL9
grub2-editenv - unset kernelopts

if grub2-mkconfig --help  | grep -- --update-bls-cmdline >/dev/null ; then
    # new scheme since RHEL 9.5 ...
    grub2-mkconfig -o /etc/grub2.cfg --update-bls-cmdline
else
    grub2-mkconfig -o /etc/grub2.cfg
fi

dracut -f -v
EOF
fi
