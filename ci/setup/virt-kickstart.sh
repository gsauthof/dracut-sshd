#!/bin/bash

# Execute unattended kickstart installation inside a VM.
#
# Something similar can be achieved with virt-install, although
# it requires root when setting the location to an ISO,
# it password-prompts on startup and it's unclear if it's supposed
# to work with netinstall ISOs.
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

img=${2:-guest.qcow2}
ks_img=${3:-ks.qcow2}
iso=${1:-CentOS-7-x86_64-NetInstall-1810.iso}
qemu=qemu-system-x86_64

qemu-img create -f qcow2 "$img" 4G

bsdtar xvf "$iso" images/pxeboot/{vmlinuz,initrd.img}

$qemu -enable-kvm -m 2G \
    -blockdev file,node-name=f1,filename="$img" \
    -blockdev qcow2,node-name=q1,file=f1 \
    -device virtio-scsi,id=vscsi \
    -device scsi-hd,drive=q1,bus=vscsi.0 \
    -netdev user,hostfwd=tcp::10023-:22,id=n1 \
    -device virtio-net,netdev=n1 \
    -serial mon:stdio -echr 2 \
    -device virtio-rng-pci \
    -cdrom "$iso" \
    -blockdev file,node-name=f2,filename=$ks_img \
    -blockdev qcow2,node-name=q2,file=f2 \
    -device virtio-blk,drive=q2 \
    -nographic \
    -kernel images/pxeboot/vmlinuz \
    -initrd images/pxeboot/initrd.img \
    -append 'initrd=initrd.img inst.stage2=hd:LABEL=CentOS\x207\x20x86_64 quiet console=tty0 console=ttyS0,115200'

echo done

