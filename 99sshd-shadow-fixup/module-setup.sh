#!/bin/bash

# 2023, Warren Togami <wtogami@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# called by dracut
check() {
    require_binaries sshd || return 1
    # 0 enables by default, 255 only on request
    return 0
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    # /etc/shadow "root:!:" allows for ssh pubkey logins on a normal system. 
    # dracut-sshd "UsePAM no" is incompatible with a '!'. Fixup to '*' which allows ssh pubkey login to work as intended.
    grep '^root:!:' "$initdir/etc/shadow" -q && sed -i -e 's/^root:!:/root:*:/' "$initdir/etc/shadow"

    return 0
}

