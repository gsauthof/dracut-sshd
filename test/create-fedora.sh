#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


if virsh --connect qemu:///system domid "$tag" ; then
    if [ "$(virsh --connect qemu:///system domstate "$tag")" = running ]; then
        virsh --connect qemu:///system shutdown "$tag"
        sync_shutdown "$tag" || true
    fi
    virsh --connect qemu:///system undefine "$tag"
fi
if virsh --connect qemu:///system domid "$tag" ; then
    virsh --connect qemu:///system destroy "$tag"
fi

rm -f "$dst"
qemu-img create -F qcow2 -b "$src" -f qcow2 "$dst" 10g

cat <<EOF > cloud-init.yml
#cloud-config
users:
  - name: root
    ssh-authorized-keys:
      - $(cat ssh-user.pub)
disable_root: false
ssh_deletekeys: true
ssh_genkeytypes: ['ed25519']
ssh_keys:
    ssh_deletekeys: true
    ssh_genkeytypes: ['ed25519']
    ed25519_private: |
$(sed 's/^/        /' host-key-ed25519)
    ed25519_public: $(cat host-key-ed25519.pub)
EOF

virt-install --connect qemu:///system \
    --name "$tag" \
    --memory 2048 \
    --network default \
    --cpu host --vcpus 2 \
    --graphics none \
    --autoconsole none \
    --import \
    --disk "$dst",format=qco2,bus=virtio \
    --osinfo fedora-unknown \
    --cloud-init user-data=cloud-init.yml


