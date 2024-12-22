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

set +e
timeout 30 $ssh root@"$guest" 'systemd-tty-ask-password-agent; sleep 60' < pw.log
r=$?
set -e
if [ $r = 124 ]; then
    echo 'Unlock timed out' >&2
    exit 1
fi
exit 0
