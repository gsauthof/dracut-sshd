#!/bin/bash

# Regenerate Kickstart config and store it in an FS image.
#
# Due to the labeling it's automatically used by Anaconda
# when present (e.g. as secondary disk in QEMU). That means
# no extra ks= kernel parameter necessary. This is an
# alternative to patching the initrd archive.
#
# Also works in bare-metal situations, e.g. when the
# filesystem is written to a USB stick.
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

{ 
    cat centos7.yaml
    echo -n 'pw: '
    cat key/pw
    echo -n 'authorized_key: "'
    tr -d '\n' < key/dracut-ssh-travis-ci-insecure-ed25519.pub 
    echo '"'
} | mustache - centos7-ks.cfg.mustache > centos7-ks.cfg


qemu-img create -f qcow2  ks.qcow2 1M
qemu-nbd --connect /dev/nbd0 ks.qcow2
mkfs.ext4 -L OEMDRV /dev/nbd0
mount -o noatime /dev/nbd0 /mnt/tmp
cp centos7-ks.cfg /mnt/tmp/ks.cfg
umount /mnt/tmp
qemu-nbd --disconnect /dev/nbd0

echo done
