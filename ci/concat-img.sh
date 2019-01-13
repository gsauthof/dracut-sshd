#!/bin/bash

# Build VM image with encrypted root FS from parts
# cf. split-img.sh for how to create these parts
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

pw=key/pw
root_img_src=root-only.qcow2.zst
root_img=${root_img_src%.zst}
prefix_img=prefix.img.zst
luks_uuid_out=key/luks-uuid

nbd_root=/dev/nbd0
nbd_guest=/dev/nbd1
luks_name=tmp
luks_uuid=$(cat $luks_uuid_out)

guest_img=guest.qcow2

[ -f $luks_uuid_out ] || {
    echo "LUKS UUID file $luks_uuid_out missing" >&2
    exit 1
}
[ -e /mnt/$luks_name ] || {
    echo "Mount point /mnt/$luks_name is missing" >&2
    exit 1
}
if [ -e /dev/mapper/$luks_name ]; then
    echo "Mapper name already in use: /dev/mapper/$luks_name" >&2
    exit 1
fi
for x in $nbd_root $nbd_guest; do
    if lsblk -n -l $x >/dev/null; then
        echo "NBD device $x already connected" >&2
        exit 1
    fi
done
for x in $root_img_src $prefix_img $luks_uuid_out $pw ; do
    [ -f $x ] || {
        echo "File $x is missing" >&2
        exit 1
    }
done

rm -f $root_img
zstd -q -d -c $root_img_src > $root_img
rm -f $guest_img
qemu-img create -f qcow2 $guest_img 4G
qemu-nbd  --connect  $nbd_guest $guest_img
zstdcat $prefix_img | dd of=$nbd_guest conv=sparse
partx -uv $nbd_guest
< pw tr -d '\n' | cryptsetup luksFormat "$nbd_guest"p4 - --uuid $luks_uuid 
< pw tr -d '\n' | cryptsetup luksOpen --key-file - "$nbd_guest"p4 $luks_name
qemu-nbd  --connect  $nbd_root $root_img
mount -o noatime $nbd_root /mnt/$luks_name
btrfs replace start -B $nbd_root /dev/mapper/$luks_name /mnt/$luks_name
umount /mnt/$luks_name
cryptsetup luksClose $luks_name
qemu-nbd --disconnect $nbd_root
qemu-nbd --disconnect $nbd_guest
rm $root_img

echo done
