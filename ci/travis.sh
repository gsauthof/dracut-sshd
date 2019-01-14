#!/bin/bash

# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eux

PS4='+${SECONDS}s '

method=$1
build_dir=${2:-build}
# cf. https://stackoverflow.com/q/59895/427158
origin="$(cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ci_dir=$origin

dist=${dracut_sshd_dist:-f29}
url_base=https://georg.so/pub/travisci/dracut-sshd/"$dist"

root_img=root-only.qcow2.zst
prefix_img=prefix.img.zst
key_arch=key.tar.gz

function download_artefacts
{
    curl --proto-redir =https -L --silent --show-error --fail \
         -O "$url_base/$root_img" \
         -O "$url_base/$prefix_img" \
         -O "$url_base/$key_arch"
}

function unpack
{
    tar xfv "$key_arch"
    cp key/{pw,known_horsts} .
    sudo mkdir -p /mnt/tmp
    sudo modprobe nbd

    # Ubuntu 16 work around cryptsetup hangs
    # cf. https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=791944#181
    # rm -f /run/udev/control
    # better workaround - install cryptsetup besides cryptsetup-bin:
    # https://bugs.launchpad.net/ubuntu/+source/cryptsetup/+bug/1589083

    sudo "$ci_dir"/concat-img.sh
    local me
    me=$(whoami)
    sudo chown "$me":"$me" guest.qcow2
}

function travis_before_install
{
    # we don't apt-get install it because that version is too old, i.e.
    # it doesn't properly raise pexpect.pxssh.ExceptionPxssh on
    # strict host key checking errors.
    local pip_flags
    pip_flags=
    if [ "${TRAVIS:-false}" != true ]; then
        pip_flags="--user"
    fi
    pip3 install $pip_flags pexpect

    # before we download anything check if there is virualization available
    echo "Verifying that (nested) virtualization is available ..."
    # As of 2019-01, travis-ci doesn't support nested virtualization
    # https://travis-ci.community/t/add-kvm-support/1406/2
    kvm-ok || true
    grep 'vmx\|svm' /proc/cpuinfo || true
    ls -l /dev/kvm || true
    echo "Verifying that (nested) virtualization is available ... done"

    if [ -e /dev/kvm ]; then
        sudo chmod 666 /dev/kvm
    fi
}

function travis_install
{
    download_artefacts
    unpack
}

function travis_script
{
    /usr/bin/python3 --version
    which python3
    python3 --version

    # use systems or the more recent one installed by travis
    python3 "$ci_dir"/test_dracut_sshd.py
}

# not an official travis target
function travis_all
{
    for i in before_install install script ; do
        travis_"$i"
    done
}

mkdir -p "$build_dir"
cd "$build_dir"
travis_"$method"

echo done

# ubuntu packages:
# btrfs-tools cpu-checker cryptsetup cryptsetup-bin curl qemu-img qemu-kvm qemu-system-x86 zstd
#
# extra packages outside travis env:
# python3-pip

