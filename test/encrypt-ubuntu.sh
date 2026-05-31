#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


rm -f root.tar.gz

guestfish -x -a "$dst" --keys-from-stdin <<EOF
run

get-uuid /dev/sda1 | tee root-uuid

mount /dev/sda1 /
tar-out / root.tar.gz compress:gzip selinux:true acls:true
umount /

wipefs /dev/sda1
part-set-name /dev/sda 1 cloudimg-rootpart
luks-format /dev/sda1 0
$(cat pw.log)
cryptsetup-open /dev/sda1 root
$(cat pw.log)

mkfs ext4 /dev/mapper/root
set-e2label /dev/mapper/root cloudimg-rootfs
<! echo set-uuid /dev/mapper/root \$(cat root-uuid)

mount /dev/mapper/root /
tar-in root.tar.gz / compress:gzip selinux:true acls:true

get-uuid /dev/sda1 | tee luks-uuid
get-uuid /dev/mapper/root | tee new-root-uuid

umount /
cryptsetup-close /dev/mapper/root

mount /dev/sda13 /
download /grub/grub.cfg grub.cfg
!sed -i 's/root=LABEL=cloudimg-rootfs/& rd.luks.uuid='\$(cat luks-uuid)'/' grub.cfg
upload grub.cfg /grub/grub.cfg


EOF
