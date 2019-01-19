
## Base Image Creation

The challenge in creating the base image is to make it as small
as possible while still keeping it realistically close to a
standard install that has an encrypted root partition. Since (by
design) an encrypted partition doesn't compress we have to
compress the unencrypted content and re-create the encrypted
volume on the target.

High-level overview of the base image and archive recreation:

1. Create the initial system image with encrypted root partition
   by calling [`configure.py`][1] (as root)
2. Run this image with `run_vm.py --unlock`
3. Copy the keys with `upload-ssh-keys.sh`
4. Run this image with `run_vm.py --unlock`
5. Make it smaller with `scp clean-in-guest.sh localhost:` and
   `ssh localhost clean-in-guest.sh`
6. Create the archives `prefix.img.zst` and `root-only.qcow2.zst`
   with `split-img.sh` (as root)

During CI, the archives are merged with `concat-img.sh` to get a
complete qcow2 image with an encrypted root partition for testing
remote unlocking via dracut-sshd.

## CentOS 7

The initial CentOS 7 image is created differently, i.e. it's
[kickstarted][ks] with Anaconda. On a high-level, it's basically:

1. Get a CentOS 7 Netinstall ISO (e.g. `CentOS-7-x86_64-NetInstall-1810.iso`)
2. Create the Kickstart config image with `create-ks-img.sh` (as
   root)
3. Execute the kickstarted Anaconda installer in a VM with
   `virt-kickstart.sh`
4. Continue with the steps in the previous section, starting with
   the 2nd item

2018, Georg Sauthoff <mail@gms.tf>


[1]: https://github.com/gsauthof/playbook/tree/master/fedora/workstation
[ks]: https://en.wikipedia.org/wiki/Kickstart_(Linux)
[an]: https://en.wikipedia.org/wiki/Anaconda_(installer)
