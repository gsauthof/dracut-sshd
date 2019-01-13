
# Filter out control sequences before printing to stdout.
#
# Use as sys.stdout replacement, e.g. supply an instance to
# the pexpect logfile parameter to get nicer output in CI
# environments.
#
# Without this the pexpect logfile output may seriously mess
# with your terminal, e.g. ESC c resets your terminal hard.
#
# 2019, Georg Sauthoff <mail@gms.tf>
# SPDX-License-Identifier: GPL-3.0-or-later

import re
import sys

noctl_exp = re.compile(b'\33c|\33\[[0-9;?]+[lmHJ]|\33\]0;')
multinl_exp = re.compile(b'\n{2,}')

class Control_Filter:
    def __init__(self, stream=None):
        if stream is None:
            stream = sys.stdout
        self.stream = stream
        self.__rest = None

    def write(self, s):
        if self.__rest is not None:
            s = self.__rest + s
            self.__rest = None
        if b'\r' in s:
            s = s.replace(b'\r', b'\n')
        if b'\n\n' in s:
            s = multinl_exp.sub(b'\n', s)
        if b'\33' in s:
            s = noctl_exp.sub(b'', s)
        i = s.rfind(b'\33')
        if i != -1:
            if i != s.find(b'\33'):
                raise RuntimeError('Unexpected escape sequence: {}'.format(s))
            self.__rest = s[i:]
            s = memoryview(s)[:i]
            #s = s[:i]
        self.stream.buffer.write(s)
        #print(s, file=sys.stderr)
        self.stream.flush()

    def flush(self):
        self.stream.flush()
