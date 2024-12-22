#!/bin/bash

set -eux

release=

if [ $# -gt 0 ]; then
    release=$1
else
    release=$(curl -sSf https://repo.almalinux.org/almalinux/ | awk -F'["/]' '/<a href=/ {print $2} ' | grep '^[0-9]\+$' | sort -n | tail -n -1)
fi

if [[ ! "$release" =~ ^[0-9]+$ ]]; then
    echo "Unexpected release number: $release" >&2
    exit 1
fi

curl -sSf -o AlmaLinux-"$release"-GenericCloud-latest.x86_64.qcow2 https://repo.almalinux.org/almalinux/"$release"/cloud/x86_64/images/AlmaLinux-"$release"-GenericCloud-latest.x86_64.qcow2


csum=$(sha256sum AlmaLinux-"$release"-GenericCloud-latest.x86_64.qcow2 | awk '{ print $1}')


curl -sSf -o checksum-"$release" https://repo.almalinux.org/almalinux/"$release"/cloud/x86_64/images/CHECKSUM

name=$(grep -v latest checksum-"$release" | awk '/^'"$csum"'/ { print $2 }' | head -n 1 | tr -d -c 'a-zA-Z0-9._-')

if [ -z "$name" ]; then
    echo "Unexpected target name: $name" >&2
    exit 1
fi

mv AlmaLinux-"$release"-GenericCloud-latest.x86_64.qcow2 "$name"

ln -sf "$name" alma"$release"-latest.x86_64.qcow2

echo "$release" > alma-release
