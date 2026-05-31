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

cat <<EOF > user-data
#cloud-config
users:
  - name: root
    ssh_authorized_keys:
      - $(cat ssh-user.pub)
disable_root: false
ssh_deletekeys: true
ssh_genkeytypes: ['ed25519']
ssh_keys:
    ed25519_private: |
$(sed 's/^/        /' host-key-ed25519)
    ed25519_public: $(cat host-key-ed25519.pub)
EOF

cat <<EOF > meta-data
instance-id: fubar
EOF

genisoimage -output cloud-init.iso -volid cidata -joliet -rock user-data meta-data


if [ $distri = ubuntu ]; then
    osinfo=ubuntu-lts-latest
else
    osinfo=fedora-unknown
fi


# NB: we aren't using
#
#     --cloud-init user-data=user-data,meta-data=meta-data
#
# due to a bug in Ubuntu's cloud images:
#
# https://github.com/canonical/cloud-init/issues/3897#issuecomment-2800021424
# https://github.com/virt-manager/virt-manager/issues/1099

virt-install --connect qemu:///system \
    --name "$tag" \
    --memory 2048 \
    --network default \
    --cpu host-model --vcpus 2 \
    --graphics none \
    --autoconsole none \
    --import \
    --disk "$dst",format=qcow2,bus=virtio \
    --disk cloud-init.iso \
    --osinfo $osinfo

wait4sshd "$tag"

# detach cloud-init.iso
virsh --connect qemu:///system  detach-disk "$tag" vdb --config
