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
prefix_img_src=prefix.qcow2.zst
luks_uuid_out=luks-uuid

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
for x in $root_img_src $prefix_img_src $luks_uuid_out $pw ; do
    [ -f $x ] || {
        echo "File $x is missing" >&2
        exit 1
    }
done

function restore_btrfs
{
    mount -o noatime $nbd_root /mnt/$luks_name
    btrfs device add /dev/mapper/$luks_name /mnt/$luks_name
    mount -o remount,rw /mnt/$luks_name
    btrfs device remove $nbd_root /mnt/$luks_name
    umount /mnt/$luks_name
    qemu-nbd --disconnect $nbd_root
    btrfstune -f -U $root_uuid /dev/mapper/$luks_name
}

function restore_xfs
{
    xfs_copy $nbd_root /dev/mapper/$luks_name
    qemu-nbd --disconnect $nbd_root
    xfs_admin -U $root_uuid /dev/mapper/$luks_name
}

sha256sum $prefix_img_src $root_img_src

rm -f $guest_img
# advantage of -o: sparse file creation
zstd -q -d $prefix_img_src -o $guest_img
rm -f $root_img
zstd -q -d $root_img_src -o $root_img

qemu-nbd  --connect  $nbd_guest $guest_img
partx -uv $nbd_guest

part=p
for i in 4 2; do
    if [ -e "$nbd_guest"p$i ]; then
        part=p$i
        break
    fi
done

< $pw tr -d '\n' | cryptsetup luksFormat "$nbd_guest"$part - --uuid $luks_uuid
< $pw tr -d '\n' | cryptsetup luksOpen --key-file - "$nbd_guest"$part $luks_name

qemu-nbd  --connect  $nbd_root $root_img
root_uuid=$(blkid $nbd_root -o value | head -n 1)
root_type=$(blkid $nbd_root -o value | tail -n 1)

# also disconnects $nbd_root
restore_$root_type

cryptsetup luksClose $luks_name

qemu-nbd --disconnect $nbd_guest
rm $root_img

echo done
