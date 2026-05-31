#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh

# download latest stable/rawhide fedora before invoking this script:
#
#     "$mydir"/get-fedora.sh "$release"
#
# cf. other get-*.sh scripts for other distributions

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

case "$distri" in
    f)
        "$mydir"/encrypt-fedora.sh "$@"
    ;;
    ubuntu)
        "$mydir"/encrypt-ubuntu.sh "$@"
    ;;
    *)
        "$mydir"/encrypt-rhel.sh "$@"
    ;;
esac

if [ "$distri" != ubuntu ]; then
    "$mydir"/update-grub.sh "$@"
fi

sync_poweron "$tag"
wait4sshd "$tag"

"$mydir"/unlock.sh "$@"

wait4sshd "$tag"

"$mydir"/verify-boot.sh "$@"
