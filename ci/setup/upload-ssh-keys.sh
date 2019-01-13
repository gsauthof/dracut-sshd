#!/bin/bash

# Provision known ssh keys to a VM
# 2019, Georg Sauthoff <mail@gms.tf>

set -eux

PS4='+${SECONDS}s '

host=localhost
port=10022
known_hosts=known_horsts
key=key/dracut-ssh-travis-ci-insecure-ed25519

scp -F /dev/null -o IdentityFile=$key \
    -o IdentitiesOnly=yes -o PreferredAuthentications=publickey \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts \
    -P $port key/ssh_host_*_key* root@localhost:/etc/ssh/

ssh -F /dev/null -o IdentityFile=$key \
    -o IdentitiesOnly=yes -o PreferredAuthentications=publickey \
    -o UserKnownHostsFile=$known_hosts \
    -p $port root@localhost <<EOF
set -x
restorecon -rv /etc/ssh
systemctl reload sshd.service
EOF

sleep 3

scp -F /dev/null -o IdentityFile=$key \
    -o IdentitiesOnly=yes -o PreferredAuthentications=publickey \
    -o UserKnownHostsFile=$known_hosts \
    -P $port key/dracut_ssh_host_*_key* root@localhost:

echo done
