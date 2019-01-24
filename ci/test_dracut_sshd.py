#!/usr/bin/env python3

# Testsuite for the dracut-ssh module
#
# Installs the module into a qemu VM and tests different unlocking
# scenarios. For example, using the right/wrong host-key for
# connecting and using different host-keys for early and late
# userspace.
#
# Doesn't use pytest as proper instantiation/parametrization of
# fixtures is kind of a pain, perhaps too much magic and the
# additonal assertion error context is too verbose.
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

import contextlib
import inspect
import logging
import os
import pexpect
import pexpect.pxssh
import sys
import tempfile
import time

import ctlseq
import run_vm
import unlock

# times 4 for non-kvm environments
login_timeout = 4 * 50
dracut_timeout = 2 * 4 * 200
shutdown_timeout = 4 * 50

boot_wait = 5
# for non-kvm environments
if os.environ.get('TRAVIS', 'false') == 'true':
    boot_wait = 4 * boot_wait

pw = open('key/pw').read().strip()
qemu = 'qemu-system-x86_64'
image = 'guest.qcow2'

key_dir = 'key'
client_key = 'dracut-ssh-travis-ci-insecure-ed25519'



# handle for the module
log = logging.getLogger(__name__)

log_format      = '{rel_secs:6.1f} {lvl}  {message}'

class Relative_Formatter(logging.Formatter):
    level_dict = { 10 : 'DBG',  20 : 'INF', 30 : 'WRN', 40 : 'ERR',
            50 : 'CRI' }
    def format(self, rec):
        rec.rel_secs = rec.relativeCreated/1000.0
        rec.lvl = self.level_dict[rec.levelno]
        return super(Relative_Formatter, self).format(rec)

def setup_logging():
    logging.basicConfig(format=log_format,
            level=logging.INFO, stream=sys.stdout)
    logging.getLogger().handlers[0].setFormatter(
            Relative_Formatter(log_format, style='{'))

def origin():
    s = inspect.getsourcefile(lambda:0)
    if not s and s == '<stdin>':
        return '.'
    else:
        return os.path.dirname(os.path.abspath(s))

def install_module(extra_keys=False):
    msg = '>> Installing module (extra_keys = {}) ...'.format(extra_keys)
    log.info(msg)
    s = run_vm.start(qemu, image, True, pw)

    time.sleep(boot_wait)

    ori = origin()
    cmd = ori + '/install-dracut-sshd.sh'
    if extra_keys:
        cmd += ' y'
    else:
        cmd += ' n'
    cmd += ' ' + ori + '/..'
    _, r = pexpect.run(cmd, withexitstatus=True,
            logfile=ctlseq.Control_Filter(),
            timeout=dracut_timeout)
    assert r in (0, 255)

    r = run_vm.wait_shutdown(s, shutdown_timeout)
    assert r == 0
    log.info(msg + ' done')

@contextlib.contextmanager
def vm():
    s = run_vm.start(qemu, image, False)
    try:
        yield s
    finally:
        s.sendline('root')
        s.expect('Password:')
        s.sendline(pw)
        s.expect('root@localhost.+#')
        s.sendline('shutdown -h now')
        r = run_vm.wait_shutdown(s, shutdown_timeout)
        assert r == 0

@contextlib.contextmanager
def known_horsts(host_key_filename):
    with tempfile.NamedTemporaryFile('w') as f: #, dir='.', delete=False) as f:
        line, host_key_algo = mk_host_key_line(host_key_filename)
        print(line, file=f, flush=True)
        known_filename = f.name
        yield known_filename, host_key_algo
            
def mk_host_key_line(filename, hostname='localhost', port='10022'):
    algo, key = open(filename).read().split()[:2]
    s = '[{}]:{} {} {}'.format(hostname, port, algo, key)
    return s, algo

def other_host_key(s):
    if s.startswith('dracut_'):
        return s[7:]
    else:
        return 'dracut_' + s

def test_unlock(m, extra_keys=False, check_host_key_fail=False, host_key_algo='ecdsa'):
    msg = '>> Testing unlocking (extra_keys = {}, check_host_key_fail = {}, host_key_algo = {}) ...'.format(extra_keys, check_host_key_fail, host_key_algo)
    log.info(msg)
    host_key = 'ssh_host_{}_key.pub'.format(host_key_algo)
    if extra_keys:
        host_key = 'dracut_' + host_key
    host_key_filename = '{}/{}'.format(key_dir, host_key)
    log.info('>>> Using host key for unlocking: ' + host_key_filename)
    other_host_key_filename = '{}/{}'.format(key_dir, other_host_key(host_key))
    key_filename = '{}/{}'.format(key_dir, client_key)
    with known_horsts(host_key_filename) as (known_filename, host_key_algo), \
            known_horsts(other_host_key_filename) as (other_known_filename, _):
        time.sleep(boot_wait)

        if check_host_key_fail:
            connection_failed = False
            try:
                unlock.unlock(pw, key_filename, other_known_filename,
                        host_key_algo)
            except pexpect.pxssh.ExceptionPxssh:
                connection_failed = True
            assert connection_failed == True

        r = unlock.unlock(pw, key_filename, known_filename, host_key_algo)
        assert r == 255

        m.expect('login:', timeout=login_timeout)
        time.sleep(boot_wait)

        if check_host_key_fail:
            connection_failed = False
            kh = known_filename if extra_keys else other_known_filename
            try:
                unlock.ssh_connect(key_filename, kh,
                        host_key_algo)
            except pexpect.pxssh.ExceptionPxssh:
                connection_failed = True
            assert connection_failed == True
        kh = other_known_filename  if extra_keys else known_filename
        s = unlock.ssh_connect(key_filename, kh, host_key_algo)
        s.sendline('hostname')
        s.expect('localhost')
        s.logout()
        s.close()
        assert s.exitstatus == 0
    log.info(msg + ' done')

def test_system(extra_keys):
    test_key = os.environ.get('dracut_sshd_test_key', 'all')
    test_fail = os.environ.get('dracut_sshd_test_fail', 'all')
    msg = '> Testing with extra_keys = {}'.format(extra_keys)
    log.info(msg)
    install_module(extra_keys)
    for host_key_algo in ('ed25519', 'ecdsa'):
        if test_key != 'all' and test_key != host_key_algo:
            continue
        for check_host_key_fail in (False, True):
            if test_fail != 'all' and (test_fail == 'true') != check_host_key_fail:
                continue
            with vm() as m:
                test_unlock(m, extra_keys=extra_keys,
                        check_host_key_fail=check_host_key_fail,
                        host_key_algo=host_key_algo)
    log.info(msg + ' ... done')

def main():
    suite = os.environ.get('dracut_sshd_suite', 'all')
    for extra_keys in ( False, True ):
        if suite == 'all' or (suite == 'extra') == extra_keys:
            test_system(extra_keys)

if __name__ == '__main__':
    setup_logging()
    sys.exit(main())

