#!/usr/bin/env python3

# Run a VM image for CI purposes inside qemu
# and possibly unlock it over the console.
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
from distutils.version import LooseVersion
import os
import pexpect
import sys

import ctlseq

# times 3 for non-kvm environments
unlock_timeout = 3 * 50
login_timeout = 3 * 50

long_timeout = 10 * 60

def mk_arg_parser():
    p = argparse.ArgumentParser(description='Start/unlock VM')
    p.add_argument('--unlock', action='store_true',
            help='unlock encrypted root filesystem (reads password from stdin)')
    p.add_argument('--qemu', '-q', default='qemu-system-x86_64',
            help='qemu command (default: qemu')
    p.add_argument('--image', '-i', default='guest.qcow2',
            help='vm image (default: guest.qcow2')
    return p

def parse_args(*a):
    arg_parser = mk_arg_parser()
    args = arg_parser.parse_args(*a)
    if args.unlock:
        args.pw = input()
    else:
        args.pw = None
    return args

def qemu_version(qemu):
    o, r = pexpect.run(qemu + ' --version', withexitstatus=True)
    assert r == 0
    i = o.find(b'version')
    assert i != -1
    v = o[i:].split()[1].decode()
    return LooseVersion(v)


def start(qemu, image, unlock, pw=None):
    v = qemu_version(qemu)
    if v < LooseVersion('3'):
        drive_flags = [ '-drive',
                'file=' + image + ',if=virtio,format=qcow2' ]
    else:
        drive_flags =  [
                '-blockdev', 'file,node-name=f1,filename=' + image,
                '-blockdev', 'qcow2,node-name=q1,file=f1',
                '-device', 'ide-hd,drive=q1', ]
    # as of 2018-01, travis-ci doesn't suppport nested virtualization:
    # https://travis-ci.community/t/add-kvm-support/1406
    if os.environ.get('TRAVIS', 'false') == 'true':
        kvm_flags = []
    else:
        kvm_flags = [ '-enable-kvm' ]
    s = pexpect.spawn(qemu,
            kvm_flags + [ '-nographic', '-m', '2G',
                # otherwise the sshd startup easily fails due to low entropy
                '-device', 'virtio-rng-pci', ] + drive_flags + [
                '-netdev', 'user,hostfwd=tcp::10022-:22,id=n1',
                '-device', 'virtio-net,netdev=n1',
                '-serial', 'mon:stdio', '-echr', '2']
            , timeout=10
            )
    #s.logfile = sys.stdout.buffer
    s.logfile = ctlseq.Control_Filter()

    # Immediately boot the default entry in the Grub menu, if possible
    # Depending on the qemu version, we might not get the Grub screen
    # over the serial line
    i = s.expect(['keys to change the selection.',
        'selected entry will be started automatically',
        'Please enter passphrase for disk.*:'], timeout=unlock_timeout)
    #s.expect("Press 'e' to edit the selected item, or 'c' for a command prompt.")
    if i < 2:
        s.sendline('')
        s.expect('Please enter passphrase for disk.*[:!]', timeout=unlock_timeout)
    if unlock:
        s.sendline(pw)
        # is only printed when qemu is running outside of pexpect?!?
        #s.expect('Starting Switch Root')
        s.expect('login:', timeout=login_timeout)
    return s

def wait_shutdown(s, timeout):
    s.expect(['reboot: Power down', 'Power down.'], timeout=timeout)
    s.expect(pexpect.EOF)
    s.close()
    return s.exitstatus

def main(*a):
    args = parse_args(*a)
    s = start(args.qemu, args.image, args.unlock, args.pw)
    if not args.unlock:
        s.expect('login:', timeout=long_timeout)
    r = wait_shutdown(s, long_timeout)
    if r != 0:
        raise RuntimeError('Exit status: {}'.format(r))

if __name__ == '__main__':
    sys.exit(main())
