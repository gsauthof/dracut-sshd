#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh

dracut_dir="$mydir"/..



guest=$(get_addr "$tag")

pushd "$dracut_dir"
$scp  example/20-wired.network  root@"$guest":/etc/systemd/network/20-wired.network
$scp  example/90-networkd.conf  root@"$guest":/etc/dracut.conf.d/90-networkd.conf
$scp  -r 46sshd  root@"$guest":/usr/lib/dracut/modules.d/


$ssh root@"$guest" <<EOF
set -eux
# make sure dhcp client gets same address in early/late boot
echo -e '\n[DHCPV4]\nClientIdentifier=mac' >> /etc/systemd/network/20-wired.network
dnf -y install dracut-network
dracut -f -v
EOF
