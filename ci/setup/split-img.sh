#!/bin/bash

# Split crypted/unencrypted parts of a VM image to save space
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

pw=pw
input_img_src=${1:-disk.qcow2}
input_img="$input_img_src".tmp
nbd_input=/dev/nbd0
nbd_root=/dev/nbd1
luks_name=tmp
zlevel=19

root_img=root-only.qcow2
prefix_img=prefix.img
luks_uuid_out=luks-uuid

[ -e /mnt/$luks_name ] || {
    echo "Mount point /mnt/$luks_name is missing" >&2
    exit 1
}
if [ -e /dev/mapper/$luks_name ]; then
    echo "Mapper name already in use: /dev/mapper/$luks_name" >&2
    exit 1
fi
for x in $nbd_input $nbd_root; do
    if lsblk -n -l $x >/dev/null; then
        echo "NBD device $x already connected" >&2
        exit 1
    fi
done
for x in $input_img_src $pw ; do
    [ -f $x ] || {
        echo "File $x is missing" >&2
        exit 1
    }
done

# we need this because the brfs replace is destructive
rm -f "$input_img"
cp --reflink=auto $input_img_src $input_img

qemu-nbd --connect $nbd_input $input_img
partx -uv $nbd_input
luks_uuid=$(blkid "$nbd_input"p4 -o value | head -n 1)

if [ -z "$luks_uuid" ]; then
    echo "Failed to get LUKS UUID" >&2
    exit 1
fi
echo $luks_uuid > $luks_uuid_out

prefix_blocks=$(sfdisk -d $nbd_input | grep "$nbd_input"p4 | tr -d , | awk '{print $4}')

# dd default bs=512
dd if=$nbd_input bs=512 count=$prefix_blocks | zstd -$zlevel > "$prefix_img".zst

< $pw tr -d '\n' | cryptsetup luksOpen --key-file - "$nbd_input"p4 $luks_name

root_size=$(lsblk /dev/mapper/$luks_name -o size --bytes -n -l)
rm -f $root_img
qemu-img create -f qcow2 $root_img $root_size

qemu-nbd --connect $nbd_root $root_img

mount -o noatime /dev/mapper/$luks_name /mnt/$luks_name

# after this, the fs on the luks volume is gone
# perhaps there is (was?) a better way:
# https://lists.fedoraproject.org/archives/list/devel@lists.fedoraproject.org/thread/BJF3SLPPIXJER7FHK3HXYBL7TLK5T2AF/#255CEALF5UIXIIRGYBMEPWPORPQWJ4AW
btrfs replace start -B /dev/mapper/$luks_name $nbd_root /mnt/$luks_name

umount /mnt/$luks_name

qemu-nbd --disconnect $nbd_root

rm -f "$root_img".zst
zstd -q -$zlevel $root_img

cryptsetup luksClose $luks_name
qemu-nbd --disconnect $nbd_input

rm "$input_img"

echo done
