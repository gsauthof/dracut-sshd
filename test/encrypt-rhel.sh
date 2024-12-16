#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


rm -f root.tar.gz

guestfish -x -a "$dst" --keys-from-stdin <<EOF
run

get-uuid /dev/sda4 | tee root-uuid

mount /dev/sda4 /
tar-out / root.tar.gz compress:gzip selinux:true acls:true
umount /

wipefs /dev/sda4
luks-format /dev/sda4 0
$(cat pw.log)
cryptsetup-open /dev/sda4 root
$(cat pw.log)

mkfs xfs /dev/mapper/root
<! echo set-uuid /dev/mapper/root \$(cat root-uuid)

mount /dev/mapper/root /
tar-in root.tar.gz / compress:gzip selinux:true acls:true

get-uuid /dev/sda4 | tee luks-uuid
get-uuid /dev/mapper/root | tee new-root-uuid

download /etc/default/grub grub
!sed -i 's/^GRUB_CMDLINE_LINUX\(_DEFAULT\|\)="[^"]*/& rd.luks.uuid='\$(cat luks-uuid)'/' grub
upload grub /etc/default/grub

umount /
cryptsetup-close /dev/mapper/root

EOF
