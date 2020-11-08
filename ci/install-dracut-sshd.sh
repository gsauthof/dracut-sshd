#!/bin/bash

# Install dracut-sshd over ssh
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

base=${2:-${dracut_ssh_base:-.}}
with_extra_keys=${1:-n}

host=localhost
port=10022
known_hosts=key/known_horsts
key=key/dracut-ssh-travis-ci-insecure-ed25519

ssh_flags=(
    -F /dev/null -o IdentityFile="$key"
    -o IdentitiesOnly=yes -o PreferredAuthentications=publickey
    -o UserKnownHostsFile="$known_hosts"
)

# work around CentOS 7 networking taking long to get ready
# in non-kvm fully emulated environment
# ssh_exchange_identification: read: Connection reset by peer
for i in $(seq 7); do
    if ssh -p $port "${ssh_flags[@]}" root@"$host" hostname ; then
        break
    fi
    sleep 1
done

scp -r -P $port "${ssh_flags[@]}" \
    "$base"/46sshd root@"$host":/usr/lib/dracut/modules.d

scp -r -P $port "${ssh_flags[@]}" \
    "$base"/example/90-networkd.conf root@"$host":/etc/dracut.conf.d

scp -r -P $port "${ssh_flags[@]}" \
    "$base"/example/90-passwordlogin.conf root@"$host":/etc/dracut.conf.d

if [ "$with_extra_keys" = y ]; then
    ssh -p $port "${ssh_flags[@]}" root@"$host" \
        cp 'dracut_ssh_host_*_key*' /etc/ssh
else
    ssh -p $port "${ssh_flags[@]}" root@"$host" \
        rm -f /etc/ssh/'dracut_ssh_host_*_key*'
fi

ssh -p $port "${ssh_flags[@]}" root@"$host" <<'EOF'
set -x
if [ ! -f /usr/lib/systemd/systemd-networkd ]; then
    sed -i 's/^\(GRUB_CMDLINE_LINUX=\)"\([^"]\+\)"/\1"\2 rd.neednet=1 ip=dhcp"/' /etc/default/grub
    grub2-mkconfig -o  /etc/grub2.cfg

    rm /etc/dracut.conf.d/90-networkd.conf /etc/dracut.conf.d/90-passwordlogin.conf
    echo 'add_dracutmodules+=" network "' > /etc/dracut.conf.d/90-network.conf
fi
dracut -f -v
shutdown -h now
EOF

echo done
