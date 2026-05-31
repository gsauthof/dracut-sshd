#!/bin/bash

set -eux

release=

if [ $# -gt 0 ]; then
    release=$1
else
    release=$(curl -sSf https://cloud-images.ubuntu.com/releases/ | awk ' /alt="\[DIR\]"/ && /href="[0-9]/ { i=index($0, "<a href="); s=substr($0, i+9); j=index(s, "/"); s=substr(s, 1, j-1); print s; }' | tr -c -d '0-9.\n' | sort -V | tail -n 1)
fi

codename=$(curl -sSf --head  https://cloud-images.ubuntu.com/releases/"$release"/ | awk -F / '/^Location:.*https:\/\/cloud-images\.ubuntu\.com\/releases\/[a-z]+\/\r$/ { print $(NF-1) }')


# NB: as of Ubuntu 26.04, only the normal cloud images come with dracut,
#     the minimal ones don't.

img="$codename"-server-cloudimg-amd64.img

curl -sSf -o "$img" https://cloud-images.ubuntu.com/resolute/current/"$img"
curl -sSf -o SHA256SUMS https://cloud-images.ubuntu.com/"$codename"/current/SHA256SUMS


csum=$(sha256sum "$img" | awk '{ print $1}')

if ! grep "^$csum" SHA256SUMS > /dev/null ; then
    echo "Checksum mismatch: $img => $csum" >&2
    exit 1
fi

ln -sf "$img" ubuntu"$release"-latest.x86_64.qcow2

echo "$release" > ubuntu-release
