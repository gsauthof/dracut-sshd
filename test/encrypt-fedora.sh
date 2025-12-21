#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


rm -f tmp.img
qemu-img create -f qcow2 tmp.img 10g


part_count=$(echo -e 'run\nlist-partitions' | guestfish -a "$dst" | wc -l)
rm -f sector-size part-list root-uuid boot-uuid luks-uuid fstab grub.cfg g2.cfg grub boot.tar.gz


if [ "$part_count" -eq 3 ]; then
    # >= f44 where /boot is a btrfs subvolume
    guestfish -x -a "$dst" -a tmp.img --keys-from-stdin <<EOF
run

get-uuid /dev/sda3 | tee root-uuid

mount /dev/sda3 /
btrfs-device-add /dev/sdb /
btrfs-device-delete /dev/sda3 /

wipefs /dev/sda3

blockdev-getss /dev/sda | tee sector-size
part-list /dev/sda | tee part-list

part-del /dev/sda 3
<! echo part-add /dev/sda p \$(awk -vss=\$(cat sector-size) '/part_start/ { print \$2/ss, \$2/ss + 1024*1024*1024/ss }' part-list | tail -n 1)
<! echo part-add /dev/sda p \$(awk -vss=\$(cat sector-size) '/part_start/ { printf "%d ", \$2/ss + 1024*1024*1024/ss + 1 } /part_end/ { print int(\$2/ss) }' part-list | tail -n 1)

tar-out /boot boot.tar.gz compress:gzip selinux:true acls:true

btrfs-subvolume-delete /boot
umount /

mkfs-btrfs /dev/sda3
mount /dev/sda3 /
btrfs-subvolume-create /boot
tar-in boot.tar.gz /boot compress:gzip selinux:true acls:true
get-uuid /dev/sda3 | tee boot-uuid
download /boot/grub2/grub.cfg g2.cfg
!sed "/^search .*--fs-uuid --set=root/s/\$(cat root-uuid)/\$(cat boot-uuid)/" g2.cfg -i
upload g2.cfg /boot/grub2/grub.cfg
umount /

mount /dev/sda2 /
download /EFI/BOOT/grub.cfg grub.cfg
!sed "s/\$(cat root-uuid)/\$(cat boot-uuid)/" grub.cfg -i
upload grub.cfg /EFI/BOOT/grub.cfg
download /EFI/fedora/grub.cfg grub.cfg
!sed "s/\$(cat root-uuid)/\$(cat boot-uuid)/" grub.cfg -i
upload grub.cfg /EFI/fedora/grub.cfg
umount /

mount /dev/sdb /
luks-format /dev/sda4 0
$(cat pw.log)
cryptsetup-open /dev/sda4 root
$(cat pw.log)
get-uuid /dev/sda4 | tee luks-uuid
btrfs-device-add /dev/mapper/root /
btrfs-device-delete /dev/sdb /
download /root/etc/fstab fstab
!sed "s@^.* /boot @UUID=\$(cat boot-uuid) /boot @" fstab -i
upload fstab /root/etc/fstab
download /root/etc/default/grub grub
!sed -i 's/^GRUB_CMDLINE_LINUX\(_DEFAULT\|\)="[^"]*/& rd.luks.uuid='\$(cat luks-uuid)'/' grub
upload grub /root/etc/default/grub
umount /
cryptsetup-close /dev/mapper/root

EOF

else # XXX delete when f43 is end-of-life

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
!sed -i 's/^GRUB_CMDLINE_LINUX\(_DEFAULT\|\)="[^"]*/& rd.luks.uuid='\$(cat luks-uuid)'/' grub
upload grub /root/etc/default/grub

umount /
cryptsetup-close /dev/mapper/root

EOF
fi
