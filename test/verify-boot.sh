#!/bin/bash

set -eux

mydir=$(dirname -- "${BASH_SOURCE[0]}")
. "$mydir"/conf.sh


guest=$(get_addr "$tag")

$ssh root@"$guest" command -v top
$ssh root@"$guest" hostnamectl


