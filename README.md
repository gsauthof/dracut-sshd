This [Dracut][dracut] module (dracut-sshd) integrates the
[OpenSSH][ossh] sshd into the [initramfs][iramfs]. It allows for
remote unlocking of a fully encrypted root filesystem and remote
access to the Dracut emergency shell (i.e. early userspace).

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
    -sh-4.4# less /run/initramfs/rdsosreport.txt
    -sh-4.4# journalctl -e
    -sh-4.4# systemctl status
    -sh-4.4# systemctl list-jobs

After fixing potential issues the emergency shell can be terminated to resume the boot:

    switch_root:/root# systemctl kill dracut-emergency.service
    switch_root:/root# Connection to 203.0.113.23 closed by remote host.
    Connection to 203.0.113.23 closed.

## Install

Copy the `46sshd` subdirectory to the [Dracut][dracut] module directory:

    # cp -ri 46sshd /usr/lib/dracut/modules.d

It's enabled, by default - unless the Dracut network module is missing. Thus:

    # dnf install -y dracut-network

(this package also contains the [`systemd-networkd`][networkd]
Dracut module)

Make sure that `/root/.ssh/authorized_keys` contains the right
keys, as it's included in the [initramfs][iramfs]:

    # cat /root/.ssh/authorized_keys

Create a non-[NetworkManager][nm] network config, e.g. via
[Networkd][networkd]:

    $ cat /etc/systemd/network/20-wired.network 
    [Match]
    Name=ens3

    [Network]
    DHCP=ipv4

Adjust the `Name=`. Even if the system doesn't have networkd
enabled (as it - say - uses NetworkManager), the sshd dracut
module unconditionally includes the networkd config files for
establishing network connectivity. However, the author of this
README strongly recommends to use Networkd instead of NetworkManager
on servers and server-like systems.

Finally regenerate the initramfs:

    # dracut -f -v

Verify that this `sshd` module is included. Either via inspecting the verbose
output or via `lsinitrd`. Reboot.


## Space Overhead

The space overhead of the [Dracut][dracut] sshd module is
negligible:

    enabled modules       initramfs size
    -----------------------------------
    vanilla               16 MiB
    +systemd-networkd     17 MiB
    +network              21 MiB
    +systemd-networkd     22 MiB
    +network +sshd

(all numbers from a Fedora 28 system)

Technically, the [`systemd-networkd`][networkd] is sufficient for
establishing some network connectivity, but including the network
module results in the inclusion of some extra network commands
(e.g. `ip`) that may be useful for troubleshooting.  Also,
depending on both `network` and `systemd-networkd` simplifies
portability between systems that have network configured either
via networkd or old-school ifcfg network scripts.

Since the [initramfs][iramfs] nowadays is actually loaded into a
[tmpfs][tmpfs] that is [freed during switch-root][switchroot] it
doesn't really pay off to safe a few mega-/kilobytes in the
initramfs. A few KiBs could be safed via switching from
[OpenSSH][ossh]'s sshd to something like [Dropbear][dropbear],
but such a alternative sshd server is likely less well audited
for security issues and supports less features (e.g. as of 2018
[Dropbear doesn't support public authentication with
ssh-ed25519][drop25519] keys). A few MiBs could be saved via
removing the network Dracut module dependency at the cost of less
flexibility in the dracut emergency shell when diagnosing network
issues.

Last but not least, in times where even embedded systems feature
hundreds of megabytes RAM, temporarily occupying a few extra
KiBs/MiBs before switch root has no dramatic impact.

## Host Keys

By default, this module includes the system's
`/etc/ssh/ssh_host_ed25519_key` private host key into the
[initramfs][iramfs]. Note that this doesn't decrease the security
in comparison with a system whose root filesystem is unencrypted:

- the generated initramfs image under /boot is only readable by
  the root user
- if an attacker is able to access the /boot/initramfs file (e.g.
  by booting the machine from a Live stick) then she is also able
  to access all host keys on a unencrypted root filesystem

That said, if the `/etc/ssh/dracut_ssh_host_ed25519_key{,.pub}`
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

## Network

An alternative to the [networkd][networkd] configuration is to
configure network via additional [Dracut command line
parameters][dracut-cmdline].

On systems without networkd (e.g. CentOS 7) this is the only way
to enable network connectivity in early userspace. For example,
the following parameters enable DHCP on all network interfaces in
early userspace:

    rd.neednet=1 ip=dhcp

They need to be appended to `GRUB_CMDLINE_LINUX=` in
`/etc/sysconfig/grub` and to be effective the Grub config then
needs to be regenerated:

    # grub2-mkconfig -o  /etc/grub2.cfg
    # grub2-mkconfig -o  /etc/grub2-efi.cfg

Note that on distributions like CentOS 7/Fedora 27/28 there is
also the old-school [ifcfg][ifcg] network scripts system under
`/etc/sysconfig/network-scripts` that can be used instead of
[NetworkManager][nm]. It can be launched via the auto-generated
`network` service that calls the old sysv init.d script. However,
the network Dracut module doesn't include neither this service
nor the network-scripts configuration. With CentOS 7/Fedora 27/28
the default network configuration uses NetworkManager which only
uses the `ifcfg-*` files under `/etc/sysconfig/network-scripts`.


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
  presence of `systemd-tty-ask-password-agent` - and it's kind of
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

[Clevis][clevis], an automatic decryption framework, has some
[LUKS][luks] unlocking and Dracut support. Looking at its documentation,
when it comes to automatic LUKS unlocking, the LUKS passphrase is
stored encrypted in the LUKS header. Clevis then decrypts it
using an external service/hardware (e.g. a [TPM] module).

The [ArchWiki dm-crypt page][arch] lists two initramfs hooks for
remote access.  Both don't use [Dracut][dracut] nor systemd,
though. Also, they use Dropbear and Tinyssh as ssh daemon.

## Tested Environments

- Fedora 28
- Fedora 27
- CentOS 7

[arch]: https://wiki.archlinux.org/index.php/Dm-crypt/Specialties#Remote_unlocking_.28hooks:_netconf.2C_dropbear.2C_tinyssh.2C_ppp.29
[bug868421]: https://bugzilla.redhat.com/show_bug.cgi?id=868421
[clevis]: https://github.com/latchset/clevis
[cryptssh]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh
[cryptssh-uwe]: https://github.com/dracut-crypt-ssh/dracut-crypt-ssh/pull/17
[dracut]: https://dracut.wiki.kernel.org/index.php/Main_Page
[dracut-cmdline]: http://man7.org/linux/man-pages/man7/dracut.cmdline.7.html
[dropbear]: https://en.wikipedia.org/wiki/Dropbear_(software)
[drop25519]: https://github.com/pts/pts-dropbear
[ifcfg]: https://www.centos.org/docs/5/html/Deployment_Guide-en-US/s1-networkscripts-interfaces.html
[iramfs]: https://en.wikipedia.org/wiki/Initial_ramdisk
[kvm]: https://en.wikipedia.org/wiki/KVM_switch#Remote_KVM_devices
[luks]: https://gitlab.com/cryptsetup/cryptsetup
[mitm]: https://en.wikipedia.org/wiki/Man-in-the-middle_attack
[networkd]: https://wiki.archlinux.org/index.php/systemd-networkd
[nm]: https://wiki.archlinux.org/index.php/NetworkManager
[ossh]: https://en.wikipedia.org/wiki/OpenSSH
[pwagent]: https://www.freedesktop.org/software/systemd/man/systemd-tty-ask-password-agent.html
[systemd]: https://en.wikipedia.org/wiki/Systemd
[switchroot]: https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
[tmpfs]: https://en.wikipedia.org/wiki/Tmpfs
[tpm]: https://en.wikipedia.org/wiki/Trusted_Platform_Module
