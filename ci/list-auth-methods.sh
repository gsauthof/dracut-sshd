#!/bin/bash

# List available authentication methods
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

host=localhost
port=10022

ssh -v -F /dev/null -o IdentityFile=/dev/null -o IdentitiesOnly=yes \
    -o PreferredAuthentications=pulibckey -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no -p $port root@"$host" true 2>&1 \
    | grep continue | head -n 1

