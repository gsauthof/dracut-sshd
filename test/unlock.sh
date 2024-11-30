#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


guest=$(get_addr "$tag")

n=$($ssh root@"$guest" systemd-tty-ask-password-agent --list | wc -l)

if [ "$n" -ne 1 ]; then
    echo 'Unexpected early boot environment' >&2
    exit 1
fi

$ssh root@"$guest" systemd-tty-ask-password-agent < pw.log



