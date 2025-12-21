#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh

# XXX download latest stable/rawhide
# "$mydir"/get-fedora.sh "$release"

if [ ! -e ssh-user.pub -o ! -e ssh-user ]; then
    ssh-keygen -t ed25519 -f $PWD/ssh-user -N ''
fi
if [ ! -e host-key-ed25519 ]; then
    ssh-keygen -t ed25519 -N '' -C '' -f host-key-ed25519
fi
if [ ! -e pw.log ]; then
    goxkcdpwgen -d - > pw.log
fi


"$mydir"/create-vm.sh "$@"

"$mydir"/install-dracut-sshd.sh "$@"

sync_shutdown "$tag"

if [ "$distri" = f ]; then
    "$mydir"/encrypt-fedora.sh "$@"
else
    "$mydir"/encrypt-rhel.sh "$@"
fi
"$mydir"/update-grub.sh "$@"

sync_poweron "$tag"
wait4sshd "$tag"

"$mydir"/unlock.sh "$@"

wait4sshd "$tag"

"$mydir"/verify-boot.sh "$@"
