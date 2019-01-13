#!/usr/bin/env python3

# Unlock a VM over ssh
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

import pexpect
from pexpect import pxssh
import sys

import ctlseq


def ssh_connect(key_filename, known_filename, host_key_algo,
        hostname='localhost', port='10022', user='root'):
    s = pxssh.pxssh(options={
        'StrictHostKeyChecking': 'yes',
        'HostKeyAlgorithms': host_key_algo,
        'UserKnownHostsFile': known_filename,
        'PreferredAuthentications': 'publickey',
        'IdentitiesOnly': 'yes',
        'IdentityFile': key_filename,
        },
        timeout=10)
    #s.logfile = sys.stdout.buffer
    s.logfile = ctlseq.Control_Filter()
    s.login(hostname, user, port=port)
    return s

def unlock(pw, key_filename, known_filename, host_key_algo,
        hostname='localhost', port='10022', user='root'):
    s = ssh_connect(key_filename, known_filename, host_key_algo,
            hostname, port, user)
    #s.prompt() # optional
    s.sendline('systemd-tty-ask-password-agent')
    s.expect('Please enter passphrase for disk .*:')
    s.sendline(pw)
    s.prompt()
    s.expect(pexpect.EOF)
    s.close()
    return s.exitstatus

def main():
    pw = open('pw').read().strip()
    r = unlock(pw, 'key/dracut-ssh-travis-ci-insecure-ed25519',
            'known_horsts', 'ecdsa-sha2-nistp256')
    if r != 255:
        raise RuntimeError('Exit status: {}'.format(r))

if __name__ == '__main__':
    sys.exit(main())

