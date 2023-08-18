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

## TOC

- [Example: Open Encrypted Root Filesystem](#example-open-encrypted-root-filesystem)
- [Example: Emergency Shell](#example-emergency-shell)
- [Install](#install)
- [Space Overhead](#space-overhead)
- [Host Keys](#host-keys)
- [Timeout](#timeout)
- [Network](#network)
- [Hardware Alternatives](#hardware-alternatives)
- [FAQ](#faq)
- [Related Work](#related-work)
- [Tested Environments](#tested-environments)
- [Packages](#packages)

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

Dracut-sshd includes the first available ssh authorized keys file of the
following list into the initramfs:

- /root/.ssh/dracut_authorized_keys
- /etc/dracut-sshd/authorized_keys
- /root/.ssh/authorized_keys

Note that on some distributions such as [Fedora
Silverblue][rpm-ostree] your only option is to create a keys file
under `/etc/dracut-sshd` as `/root` isn't accessible during
`dracut` runtime.

Of course, our initramfs image needs network support. The simplest
way to achieve this is to include [networkd][networkd]. To install
the networkd dracut module:

    # dnf install -y dracut-network

When installing from copr, `dracut-network` is automatically
installed as dependency.

Create a non-[NetworkManager][nm] network config, e.g. via
[Networkd][networkd]:

```
$ cat /etc/systemd/network/20-wired.network
[Match]
Name=e*

[Network]
DHCP=ipv4
```

Adjust the `Name=`, if necessary.

Note that the dracut networkd module doesn't include the system's
network configuration files by default and note that the module
isn't enabled, by default, either. Thus, you have to configure
Dracut for networkd (cf. the [install_items][iitems] and
[add_dracutmodules][addmod] directives). Example:

```
# cat /etc/dracut.conf.d/90-networkd.conf
install_items+=" /etc/systemd/network/20-wired.network "
add_dracutmodules+=" systemd-networkd "
```

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

Note that Ubuntu's dracut defaults to an initramfs filename that
is incompatible with Ubuntu's grub default initrd settings ... m(
Thus, on Ubuntu one has to explicitly specify the initramfs filename like this:

    # dracut -f -v /boot/initrd.img-$(uname -r)

Verify that this `sshd` module is included. Either via inspecting the verbose
output or via `lsinitrd`, e.g.:

    # lsinitrd | grep 'authorized\|bin/sshd\|network/20'
    -rw-r--r--   1 root     root          119 Jul 17 15:08 etc/systemd/network/20-wired.network
    -rw-------   1 root     root           99 Jul 17 17:04 root/.ssh/authorized_keys
    -rwxr-xr-x   1 root     root       876328 Jul 17 17:04 usr/sbin/sshd

Finally, reboot.


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
for security issues and supports less features (e.g. ssh-ed25519
public key authentication was only [added as late as
2020][drop25519], and, as of 2021, there are some [interoperability
issues][drop25519b] and [ed25519-sk keys aren't
supported][dropsk]).

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
- Why do I get `Permission denied (publickey)` although the same
  authorized key works after the system is booted?

  A: This can be caused by a root account that is locked with `!`
  instead of `*`. In that case it's enough to change the lock
  method (or set a password) and regenerate the initramfs.
  Background: On some systems Dracut also includes `/etc/shadow`
  which is then used by sshd. In early userspace, there is no
  PAM, thus sshd uses built-in code for shadow handling. In
  contrast to usual PAM configuration (which is used by late
  userspace sshd, by default), sshd itself differentiates
  between `*` and `!` as invalid password field tokens. Meaning
  that only `*` allows public key authentication while `!` blocks
  any login ([see also][i30]).
- Can I use dracut-sshd when my root account is locked?

  A: Yes, you can.
  However, you have to make sure that your account isn't locked
  with a `!` in `/etc/shadow`. If it is locked like that, you
  have to lock it differently, e.g. via `usermod -p '*' root`
  or simply set a strong password for the root user, followed
  by `dracut -f`.
  See also the previous question for additional details.
- Does dracut-sshd only work with networkd?

  A: No, it doesn't.
  Dracut-sshd is network service agnostic.
  It just requires the network being online during early boot.
  Depending on the distribution, there might be different
  alternatives available for bringing network
  interfaces up early, such as Systemd's networkd, legacy network
  scripts, NetworkManager etc.
  A given distribution and release might support one of those
  or many, and default to one of them when the `network` dracut
  module is included.
  Besides selecting a specific dracut network module, there are
  also dracut cmdline parameters for configuring network options
  and addresses.
  Depending on your concrete network setup and distribution, a
  certain network module might be more suitable than another.
  In general, it isn't an issue to use one network service during
  early boot and another for late boot (e.g. networkd and
  NetworkManager).
  The same goes for configurations, e.g. perhaps for early boot a
  simple DHCP setups makes most sense while in late boot you have a
  more complicated network configuration.
- How do I make it work on Ubuntu 20.04?

  A: There are some pitfalls on Ubuntu. Firstly, dracut isn't
  installed by default (fix: `apt install dracut-core
  dracut-network`). Secondly, dracut isn't a first class citizen
  on Ubuntu (i.e. it's only included in the universe repository,
  not in the main repository). As a result, the default dracut
  initramfs filename doesn't match what Ubuntu uses in its
  Grub configuration. Thus, you have to explicitly specify
  the right one (i.e. `/boot/initrd.img-$(uname -r)`) in the
  `dracut` and `lsinitrd` commands.
- How do I debug dracut-sshd issues in the early boot
  environment?

  A: You start by dropping into the dracut emergency shell and
  looking at the journal and status of the involved services.
  For example, via `systemctl status sshd.service`, `journalctl
  -u sshd` etc. You drop into the emergency shell by adding
  `rd.break` (and possibly `rd.shell`) to kernel parameter
  command-line. Of course, you need some kind of console
  access when doing such debugging. Using a virtual machine
  usually is sufficient to reproduce issues which simplifies
  things.

## Related Work

There is the [unmaintained][cryptssh-unm] (since 2019 or earlier)
[dracut-crypt-ssh][cryptssh] module which aimed to provide SSH
access for remotely unlocking an encrypted LUKS volume. Main
differences to dracut-sshd:

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

In 2017, a [dracut-crypt-ssh pull request][cryptssh-uwe] added
support for optionally using OpenSSH's sshd instead of Dropbear,
without changing the other differences. It was closed without
being merged in 2021.

There are also some other dracut modules that use Dropbear:
[mk-fg/dracut-crypt-sshd][mkfg] which was marked
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

The [ArchWiki dm-crypt page][arch] lists two initramfs hooks for
remote access.  Both don't use [Dracut][dracut] nor systemd,
though. Also, they use Dropbear and Tinyssh as ssh daemon.

[Clevis][clevis], an automatic decryption framework, has some
[LUKS][luks] unlocking and Dracut support. Looking at its documentation,
when it comes to automatic LUKS unlocking, the LUKS passphrase is
stored encrypted in the LUKS header. Clevis then decrypts it
using an external service/hardware (e.g. a [Tang][tang] server
or a [TPM] module).

Similar to Clevis, [Mandos][mandos] also implements a framework
for unattended LUKS unlocking. Unlike Clevis, it primarily
targets Debian and doesn't support TPM. That means for unlocking
the Mandos client fetches the asymmetrically encrypted LUKS
password from a Mandos server.

With version 248 (i.e. available since early 2021 or so),
[systemd integrated some automatic LUKS2 volume unlocking
features][systemd248]. Similar to Clevis it supports TPM2 modules.
In addition, it also supports smart cards and FIDO2/hmac-secret
devices. At least some of those FIDO2 devices seem to support
non-interactive HMAC computation and thus allow to auto-unlock
LUKS volumes as long as the enrolled FIDO2 device is connected.

If your threat model goes beyond what is described in the [Host
Keys](#host-keys) Section, you have to look into [authenticated
boot and disk encryption][authboot].

Although enterprise motherboard and server vendors often
integrate unpleasant BMCs (cf. the [Hardware Alternatives
Section](#hardware-alternatives)), a hardware solution for remote
access to early boot doesn't have to be awful. For example, there is
the open and DIY [Pi-KVM][pikvm] project which looks quite
promising.

Related Fedora ticket: [Bug 524727 - Dracut + encrypted root + networking (2009)][bug524727]

## Tested Environments

- Fedora Silverblue 33
- Fedora 27 to 38
- CentOS 7, 8
- CentOS Stream 9 (by a contributor)
- RHEL 8 beta 1
- Rocky Linux 8.8, 9 (by a contributor)
- Gentoo (by a contributor)
- SUSE (by a contributor)
- openSUSE Leap 15.5
- Arch (by a contributor)
- Ubuntu 20.04 LTS
- Debian 12 (by a contributor)


## Packages

- [Copr][copr] - for Fedora, EPEL (i.e. RHEL or RHEL clones such
  as AlmaLinux or Rocky)
- [openSUSE](https://build.opensuse.org/package/show/openSUSE:Factory/dracut-sshd)
- [Arch AUR](https://aur.archlinux.org/packages/dracut-sshd-git)

[arch]: https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlocking_.28hooks:_netconf.2C_dropbear.2C_tinyssh.2C_ppp.29
[bls]: https://systemd.io/BOOT_LOADER_SPECIFICATION
[bug524727]: https://bugzilla.redhat.com/show_bug.cgi?id=524727
[bug868421]: https://bugzilla.redhat.com/show_bug.cgi?id=868421
[clevis]: https://github.com/latchset/clevis
[copr]: https://copr.fedorainfracloud.org/coprs/gsauthof/dracut-sshd/
[cryptssh]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh
[cryptssh-uwe]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh/pull/17
[cryptssh-unm]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh/issues/43
[dracut]: https://dracut.wiki.kernel.org/index.php/Main_Page
[dracut-cmdline]: https://manpath.be/f32/7/dracut.cmdline
[dropbear]: https://en.wikipedia.org/wiki/Dropbear_(software)
[drop25519]: https://github.com/mkj/dropbear/pull/91
[drop25519b]: https://github.com/mkj/dropbear/issues/136#issuecomment-913134728
[dropsk]: https://github.com/mkj/dropbear/issues/135
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
[systemd248]: http://0pointer.net/blog/unlocking-luks2-volumes-with-tpm2-fido2-pkcs11-security-hardware-on-systemd-248.html
[switchroot]: https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
[tmpfs]: https://en.wikipedia.org/wiki/Tmpfs
[tpm]: https://en.wikipedia.org/wiki/Trusted_Platform_Module
[addmod]: https://manpath.be/f32/dracut/050-26.git20200316.fc32.x86_64/5/dracut.conf#L74
[port]: https://github.com/gsauthof/dracut-sshd/issues/9#issuecomment-531308602
[entropy]: https://github.com/gsauthof/dracut-sshd/issues/12
[iitems]: https://manpath.be/f32/dracut/050-26.git20200316.fc32.x86_64/5/dracut.conf#L74
[i30]: https://github.com/gsauthof/dracut-sshd/issues/30
[rpm-ostree]: https://discussion.fedoraproject.org/t/using-dracut-sshd-to-unlock-a-luks-encrypted-system/23449/6
[pikvm]: https://github.com/pikvm/pikvm
[authboot]: https://0pointer.net/blog/authenticated-boot-and-disk-encryption-on-linux.html
[tang]: https://github.com/latchset/tang
[mandos]: https://www.recompile.se/mandos
[debian-package-git]: https://wiki.debian.org/PackagingWithGit
[git-buildpackage]: https://honk.sigxcpu.org/piki/projects/git-buildpackage/ 