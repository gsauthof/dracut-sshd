
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
2. Make it smaller with `scp clean-in-guest.sh localhost:` and
   `ssh localhost clean-in-guest.sh`
3. Copy the keys with `upload-ssh-keys.sh`
4. Create the archives `prefix.img.zst` and `root-only.qcow2.zst`
   with `split-img.sh` (as root)

During CI, the archives are merged with `concat-img.sh` to get a
complete qcow2 image with an encrypted root partition for testing
remote unlocking via dracut-sshd.

2018, Georg Sauthoff <mail@gms.tf>


[1]: https://github.com/gsauthof/playbook/tree/master/fedora/workstation
