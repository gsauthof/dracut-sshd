#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


rm -f tmp.img
qemu-img create -f qcow2 tmp.img 10g

guestfish -x -a "$dst" -a tmp.img --keys-from-stdin <<EOF
run

get-uuid /dev/sda4 | tee root-uuid

mount /dev/sda4 /
btrfs-device-add /dev/sdb /
btrfs-device-delete /dev/sda4 /

wipefs /dev/sda4
luks-format /dev/sda4 0
$(cat pw.log)
cryptsetup-open /dev/sda4 root
$(cat pw.log)
btrfs-device-add /dev/mapper/root /
btrfs-device-delete /dev/sdb /

get-uuid /dev/sda4 | tee luks-uuid
get-uuid /dev/mapper/root | tee new-root-uuid

download /root/etc/default/grub grub
!sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=".\+\)"/\1 rd.luks.uuid='\$(cat luks-uuid)'"/' grub
upload grub /root/etc/default/grub
umount /
cryptsetup-close /dev/mapper/root

EOF
