#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


guestfish -x -a "$dst" -f "$mydir"/update-grub.guestf
