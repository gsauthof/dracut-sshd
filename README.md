[![Build Status](https://travis-ci.org/gsauthof/dracut-sshd.svg?branch=master)](https://travis-ci.org/gsauthof/dracut-sshd)
[![Copr Build Status](https://copr.fedorainfracloud.org/coprs/gsauthof/dracut-sshd/package/dracut-sshd/status_image/last_build.png)](https://copr.fedorainfracloud.org/coprs/gsauthof/dracut-sshd/)

This [Dracut][dracut] module (dracut-sshd) integrates the
[OpenSSH][ossh] sshd into the [initramfs][iramfs]. It allows for
remote unlocking of a fully encrypted root filesystem and remote
access to the Dracut emergency shell (i.e. early userspace).

It's compatible with systems that use Dracut as initramfs manager
and systemd as init system, such as Fedora, CentOS/RHEL (version
7 or greater) and SUSE. Gentoo is also to known to work with
dracut-sshd, as long as it's configured with systemd and Dracut.

2018, Georg Sauthoff <mail@gms.tf>, GPLv3+

## Example: Open Encrypted Root Filesystem

After booting a Fedora system with encrypted root filesystem
(i.e. a filesystem on a [LUKS volume to be opened with
cryptsetup][luks]) the [Dracut][dracut] [initramfs][iramfs]
blocks at the password prompt. With dracut-sshd enabled remote
unlocking is then as simple as:

    $ ssh headless.example.org
    -sh-4.4# systemd-tty-ask-password-agent       
    Please enter passphrase for disk luks-123-cafe! *********
    Please enter passphrase for disk luks-124-cafe! *********
    -sh-4.4# Connection to 203.0.113.23 closed by remote host.
    Connection to 203.0.113.23 closed.

That means under normal circumstances the completion of all
password prompts automatically resumes the boot process.

The command [`systemd-tty-ask-password-agent --list`][pwagent] prints an overview
over all pending password prompts.

## Example: Emergency Shell

The start of the [Dracut][dracut] emergency shell can be
requested via adding `rd.break` to the kernel command line, but
it also happens when Dracut is unable to mount the root
filesystem or other grave issues. In such cases the emergency
shell blocks the boot process. Without remote access the machine
is quite dead then.

Example session:

    $ ssh headless.example.org
    -sh-4.4# export TERM=vt220
    -sh-4.4# export SYSTEMD=FRMXK
    -sh-4.4# export LC_ALL=C
    -sh-4.4# less /run/initramfs/rdsosreport.txt
    -sh-4.4# journalctl -e
    -sh-4.4# systemctl status
    -sh-4.4# systemctl list-jobs

After fixing potential issues the emergency shell can be terminated to resume the boot:

    switch_root:/root# systemctl stop dracut-emergency.service
    switch_root:/root# Connection to 203.0.113.23 closed by remote host.
    Connection to 203.0.113.23 closed.

Alternatively, one can send a signal to the emergency service, e.g.
with `systemctl kill ...` or `systemctl kill --signal=... ...`.

## Install

Copy the `46sshd` subdirectory to the [Dracut][dracut] module directory:

    # cp -ri 46sshd /usr/lib/dracut/modules.d

Alternatively, you can install the latest stable version from the
[dracut-sshd copr repository][copr].

Either way, once present under `/usr/lib/dracut/modules.d` it's
enabled, by default.

With an sshd that lacks systemd support (e.g. under Gentoo), one
has to adjust the systemd service file:

    # echo 'Skip this sed on Fedora/RHEL/CentOS/Debian/Ubuntu/...!'
    # sed -e 's/^Type=notify/Type=simple/' \
          -e 's@^\(ExecStart=/usr/sbin/sshd\) -D@\1 -e -D@' \
          -i \
          /usr/lib/dracut/modules.d/46sshd/sshd.service

Make sure that `/root/.ssh/authorized_keys` contains the right
keys, as it's included in the [initramfs][iramfs]:

    # cat /root/.ssh/authorized_keys

That said, if `/root/.ssh/dracut_authorized_keys` is present
then it is included, instead.

Of course, our initramfs image needs network support. The simplest
way to achieve this is to include [networkd][networkd]. To install
the networkd dracut module:

    # dnf install -y dracut-network

When installing from copr, `dracut-network` is automatically
installed as dependency.

Create a non-[NetworkManager][nm] network config, e.g. via
[Networkd][networkd]:

    $ cat /etc/systemd/network/20-wired.network 
    [Match]
    Name=e*

    [Network]
    DHCP=ipv4

Adjust the `Name=`, if necessary.

Note that the dracut networkd module doesn't include the system's
network configuration files by default and note that the module
isn't enabled, by default, either. Thus, you have to configure
Dracut for networkd (cf. the [install_items][iitems] and
[add_dracutmodules][addmod] directives). Example:

    # cat /etc/dracut.conf.d/90-networkd.conf
    install_items+=" /etc/systemd/network/20-wired.network "
    add_dracutmodules+=" systemd-networkd "

Alternatively, early boot network connectivity can be configured
by other means (i.e.  kernel parameters, see below).  However,
the author of this README strongly recommends to use Networkd
instead of NetworkManager on servers and server-like systems.

If the above example is sufficient you just need to copy the
example configuration files from the `example/` subdirectory:

    # cp example/20-wired.network  /etc/systemd/network
    # cp example/90-networkd.conf /etc/dracut.conf.d

Finally regenerate the initramfs:

    # dracut -f -v

Verify that this `sshd` module is included. Either via inspecting the verbose
output or via `lsinitrd`. Reboot.


## Space Overhead

The space overhead of the [Dracut][dracut] sshd module is
negligible:

    enabled modules           initramfs size
    --------------------------------------
    vanilla -network -ifcfg   16 MiB
    +systemd-networkd         17 MiB
    +systemd-networkd +sshd   19 MiB
    +network +ifcfg           21 MiB
    +network +ifcfg +sshd     21 MiB
    +network +ifcfg +sshd     22 MiB
    +systemd-networkd

(all numbers from a Fedora 28 system, measuring the compressed
initramfs size)

Technically, the [`systemd-networkd`][networkd] Dracut module is
sufficient for establishing network connectivity. It even
includes the `ip` command. Since the network Dracut module is
included by default (under CentOS 7/Fedora 27/28) via the
[ifcfg][ifcfg]
Dracut module, it may make sense to explicitly exclude it when
building the initramfs on a system where networkd is available,
e.g. via

    dracut -f -v --omit ifcfg

as this saves a few megabytes.

Since the [initramfs][iramfs] is actually loaded into a
[tmpfs][tmpfs] that is [freed during switch-root][switchroot] it
doesn't really pay off to safe a few mega-/kilobytes in the
initramfs. A few KiBs could be saved via switching from
[OpenSSH][ossh]'s sshd to something like [Dropbear][dropbear],
but such an alternative sshd server is likely less well audited
for security issues and supports less features (e.g. as of 2018
[Dropbear doesn't support public authentication with
ssh-ed25519][drop25519] keys).

Last but not least, in times where even embedded systems feature
hundreds of megabytes RAM, temporarily occupying a few extra
KiBs/MiBs before switch root has no dramatic impact.

## Host Keys

By default, this module includes the system's
`/etc/ssh/ssh_host_*_key` private host keys into the
[initramfs][iramfs]. Note that this doesn't decrease the security
in comparison with a system whose root filesystem is unencrypted:

- the generated initramfs image under /boot is only readable by
  the root user
- if an attacker is able to access the /boot/initramfs file (e.g.
  by booting the machine from a Live stick) then she is also able
  to access all host keys on a unencrypted root filesystem

That said, if `/etc/ssh/dracut_ssh_host_*_key{,.pub}`
files are present then those are included, instead.

As always, it depends on your threat model, whether it makes
sense to use an extra host key for the initramfs or not. Using an
extra key may complicate the life of an attacker who is able to
read out the initramfs content but is unable to change it and
thus the attacker has to wait for the next SSH connection to the
initramfs before being able to perform a [MITM attack][mitm]. On
the other hand, when the attacker is able to change to initramfs
image then an extra key doesn't provide more security than using
the system's host key as the attacker can intercept the entered
password, anyway.

If your primary threat model is an attacker who gets access to
decommissioned but still readable hard-disks, then the system's
host key in the initramfs image  provides no value to the
attacker given that the root filesystem is fully encrypted (and
that the host key isn't reused in the replacement system).

## Timeout

With recent Fedora versions (e.g. Fedora 28) a cryptsetup
password prompt shouldn't timeout. If it does then it's a
regression (cf. [Bug 868421][bug868421]). Even if it times out
and [Dracut][dracut] drops into the emergency shell then remotely
connecting to it should still work with this module.  In such
situations [`systemd-tty-ask-password-agent`][pwagent] should
still work.  See also Section 'Example: Emergency Shell' on how
to resume the boot process then.

A simple way to trigger the timeout is to enter the wrong
password 3 times when unlocking a LUKS volume. Under Fedora 28,
the timeout is then 2 minutes or so long, i.e. the emergency
shell is then started after 2 minutes, by default, even without
explicitly adding `rd.shell` to the kernel command line. One can
recover from such a situation with e.g.:

    # systemctl restart 'systemd-cryptsetup@*'

Another example for the emergency shell getting started is that
a device that is necessary for mounting the root filesystem
simply isn't attached - or the UUIDs specified on the kernel
command line don't match. After inspecting the situation with
`systemctl status ...`, `journalctl -e`, etc. one can
regenerate some config and restart the appropriate services in a
similar fashion.

## Network

An alternative to the [networkd][networkd] configuration is to
configure network via additional [Dracut command line
parameters][dracut-cmdline].

This requires the activation of the network dracut module, e.g.:

    # cat /etc/dracut.conf.d/90-network.conf
    add_dracutmodules+=" network "

On systems without networkd (e.g. CentOS 7/RHEL 8) this is the only way
to enable network connectivity in early userspace. For example,
the following parameters enable DHCP on all network interfaces in
early userspace:

    rd.neednet=1 ip=dhcp

They need to be appended to `GRUB_CMDLINE_LINUX=` in
`/etc/default/grub` and to be effective the Grub config then
needs to be regenerated:

    # grub2-editenv - unset kernelopts
    # grub2-mkconfig -o /etc/grub2.cfg
    # grub2-mkconfig -o /etc/grub2-efi.cfg

Note that on distributions like CentOS 7/Fedora 27/28 there is
also the old-school [ifcfg][ifcfg] network scripts system under
`/etc/sysconfig/network-scripts` that can be used instead of
[NetworkManager][nm]. It can be launched via the auto-generated
`network` service that calls the old sysv init.d script. However,
the network Dracut module doesn't include neither this service
nor the network-scripts configuration (it includes some of the
scripts but the Dracut modules auto-generate the configuration
during early userspace boot based on the kernel
command line/detected hardware). With CentOS 7/Fedora 27/28 the
default network configuration (in late userspace) uses
NetworkManager which only uses the `ifcfg-*` files under
`/etc/sysconfig/network-scripts`.

The `grub2-editenv` call is only necessary on systems (such as
RHEL 8) where the kernel parameters are stored in `/etc/grubenv`
instead of in each menu entry (either in the main `grub2.cfg` or
under `/boot/loader/entries` if the system follows the [boot
loader specification (bls)][bls]).


## Hardware Alternatives

A Baseboard Management Controller (BMC) or some kind of [remote KVM][kvm]
device can help with early boot issues, however:

- not all remote machines even have a BMC
- the BMC often is quite tedious to use and buggy
- the BMC often contains low quality proprietary software that is
  never updated and likely contains many security issues
- in some hosting environments a KVM must be manually attached
  and is charged at an hourly rate. That means you end up paying
  the remote hands for attaching the KVM, plus possibly an extra
  charge if you need it outside business hours and the hourly rate.

Thus, as a general rule, one wants to avoid a BMC/KVM as much as
possible.

## FAQ

- How to make the early boot sshd listen on a non-standard port?
  A: If you really [want to do that][port] you can provide a
  `/etc/sysconfig/dracut-sshd` that defines `SSHD_OPTS`
  ([see also][port]).
- Why does sshd hangs during early-boot when running dracut-sshd
  inside a virtual machine (VM)?
  A: Most likely the VM guest is short of entropy and thus sshd
  blocks during startup (without logging a warning) for an
  indefinite amount of time. Possible up to the systemd service
  restart timeout. Directing some of the VM host's entropy into
  the VM guest fixes this issue ([cf. these comments for
  examples of how to do this][entropy]).

## Related Work

There is [dracut-crypt-ssh][cryptssh] module which aims to
provide SSH access for remotely unlocking an encrypted LUKS
volume. Main differences to dracut-sshd:

- uses [Dropbear][dropbear] instead of [OpenSSH][ossh] sshd (cf. the Space
  Overhead Section for the implications)
- doesn't use [systemd][systemd] for starting/stopping the Dropbear daemon
- generates a new set of host keys, by default
- listens on a non-standard port for ssh, by default
- arguably more complex than dracut-sshd - certainly more lines
  of code and some options
- comes with an unlock command that is superfluous in the
  presence of [`systemd-tty-ask-password-agent`][pwagent] - and it's kind of
  dangerous to use, e.g. when the password prompt times out the
  password is echoed to the console

A [dracut-crypt-ssh pull request][cryptssh-uwe] (open as
of 2018) for optionally using OpenSSH's sshd instead of Dropbear.
Main differences to dracut-sshd:

- doesn't use systemd for starting/stopping the sshd daemon
- generates a new set of host keys, by default
- listens on a non-standard port for ssh, by default
- arguably more complex than dracut-sshd - certainly more lines
  of code and some options
- unlock command still present
- pull-request evolved via additional commits without cleanup rebases

There is [mk-fg/dracut-crypt-sshd][mkfg] which was marked
deprecated in 2016 in favour of the above dracut-crypt-ssh. It
uses Dropbear and some console hacks instead of
`systemd-tty-ask-password-agent`.
[mdcurtis/dracut-earlyssh][mdcurtis] is a fork
mk-fg/dracut-crypt-sshd. The main difference is that it also
suppports RHEL 6 (which features a quite different version of
dracut). [xenoson/dracut-earlyssh][xenoson] is a fork of
mdcurtis/dracut-earlyssh. It has RHEL 6 support removed and some
questionable helpers removed. It creates a systemd unit file for
Dropbear although it still explicitly starts/stops it via hook
files instead of making use of the systemd dependency features.

[Clevis][clevis], an automatic decryption framework, has some
[LUKS][luks] unlocking and Dracut support. Looking at its documentation,
when it comes to automatic LUKS unlocking, the LUKS passphrase is
stored encrypted in the LUKS header. Clevis then decrypts it
using an external service/hardware (e.g. a [TPM] module).

The [ArchWiki dm-crypt page][arch] lists two initramfs hooks for
remote access.  Both don't use [Dracut][dracut] nor systemd,
though. Also, they use Dropbear and Tinyssh as ssh daemon.

Related ticket: [Bug 524727 - Dracut + encrypted root + networking (2009)][bug524727]

## Tested Environments

- Fedora 27 to 32
- CentOS 7, 8
- RHEL 8 beta 1
- Gentoo (by a contributor)
- SUSE (by a contributor)
- Arch (by a contributor)

[arch]: https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlocking_.28hooks:_netconf.2C_dropbear.2C_tinyssh.2C_ppp.29
[bls]: https://systemd.io/BOOT_LOADER_SPECIFICATION
[bug524727]: https://bugzilla.redhat.com/show_bug.cgi?id=524727
[bug868421]: https://bugzilla.redhat.com/show_bug.cgi?id=868421
[clevis]: https://github.com/latchset/clevis
[copr]: https://copr.fedorainfracloud.org/coprs/gsauthof/dracut-sshd/
[cryptssh]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh
[cryptssh-uwe]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh/pull/17
[dracut]: https://dracut.wiki.kernel.org/index.php/Main_Page
[dracut-cmdline]: https://manpath.be/f32/7/dracut.cmdline
[dropbear]: https://en.wikipedia.org/wiki/Dropbear_(software)
[drop25519]: https://github.com/pts/pts-dropbear
[ifcfg]: https://www.centos.org/docs/5/html/Deployment_Guide-en-US/s1-networkscripts-interfaces.html
[iramfs]: https://en.wikipedia.org/wiki/Initial_ramdisk
[kvm]: https://en.wikipedia.org/wiki/KVM_switch#Remote_KVM_devices
[luks]: https://gitlab.com/cryptsetup/cryptsetup
[mitm]: https://en.wikipedia.org/wiki/Man-in-the-middle_attack
[mkfg]: https://github.com/mk-fg/dracut-crypt-sshd
[mdcurtis]: https://github.com/mdcurtis/dracut-earlyssh
[xenoson]: https://github.com/xenoson/dracut-earlyssh
[networkd]: https://wiki.archlinux.org/index.php/systemd-networkd
[nm]: https://wiki.archlinux.org/index.php/NetworkManager
[ossh]: https://en.wikipedia.org/wiki/OpenSSH
[pwagent]: https://manpath.be/f32/1/systemd-tty-ask-password-agent
[systemd]: https://en.wikipedia.org/wiki/Systemd
[switchroot]: https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
[tmpfs]: https://en.wikipedia.org/wiki/Tmpfs
[tpm]: https://en.wikipedia.org/wiki/Trusted_Platform_Module
[addmod]: https://manpath.be/f32/dracut/050-26.git20200316.fc32.x86_64/5/dracut.conf#L74
[port]: https://github.com/gsauthof/dracut-sshd/issues/9#issuecomment-531308602
[entropy]: https://github.com/gsauthof/dracut-sshd/issues/12
[iitems]: https://manpath.be/f32/dracut/050-26.git20200316.fc32.x86_64/5/dracut.conf#L74

