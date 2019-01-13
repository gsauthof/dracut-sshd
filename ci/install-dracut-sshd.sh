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
known_hosts=known_horsts
key=key/dracut-ssh-travis-ci-insecure-ed25519

ssh_flags=(
    -F /dev/null -o IdentityFile="$key"
    -o IdentitiesOnly=yes -o PreferredAuthentications=publickey
    -o UserKnownHostsFile="$known_hosts"
)

scp -r -P $port "${ssh_flags[@]}" \
    "$base"/46sshd root@"$host":/usr/lib/dracut/modules.d

if [ "$with_extra_keys" = y ]; then
    ssh -p $port "${ssh_flags[@]}" root@"$host" \
        cp 'dracut_ssh_host_*_key*' /etc/ssh
else
    ssh -p $port "${ssh_flags[@]}" root@"$host" \
        rm -f /etc/ssh/'dracut_ssh_host_*_key*' 
fi

ssh -p $port "${ssh_flags[@]}" root@"$host" <<EOF
set -x
dnf install -y dracut-network
dracut -f -v
shutdown -h now
EOF

echo done
