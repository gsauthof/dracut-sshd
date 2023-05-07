Name:       {{{ git_dir_name }}}
# The git_dir_version macro is quite a mis-match for our use-case
# since using a 3-component version number requires updating
# the 'lead' parameter, anyways
# cf. https://pagure.io/rpkg-util/issue/21#comment-601077
#Version:    {{{ git_dir_version }}}
Version:    0.6.4
Release:    1%{?dist}
Summary:    Provide SSH access to initramfs early user space
URL:        https://github.com/gsauthof/dracut-sshd
License:    GPLv3+
VCS:        {{{ git_dir_vcs }}}
Source:     {{{ git_dir_pack }}}
BuildArch:  noarch
Requires:   dracut-network

%description
This Dracut module integrates the OpenSSH sshd into your
initramfs. It allows for remote unlocking of a fully encrypted
root filesystem and remote access to the Dracut emergency shell
(i.e. early userspace).

%prep
{{{ git_dir_setup_macro }}}

%build
# nothing to do here

%install
mkdir -p %{buildroot}/usr/lib/dracut/modules.d
cp -r 46sshd %{buildroot}/usr/lib/dracut/modules.d/

%files
/usr/lib/dracut/modules.d/46sshd/module-setup.sh
/usr/lib/dracut/modules.d/46sshd/sshd.service
/usr/lib/dracut/modules.d/46sshd/motd
/usr/lib/dracut/modules.d/46sshd/profile
%config(noreplace) /usr/lib/dracut/modules.d/46sshd/sshd_config
%doc README.md
%doc example/20-wired.network
%doc example/90-networkd.conf

%changelog
* Sun May 7 2023 Georg Sauthoff <mail@gms.tf> - 0.6.4-1
- fix motd

* Sat May 1 2021 Georg Sauthoff <mail@gms.tf> - 0.6.3-1
- fix privilege separation directory for Fedora 34

* Sun Nov 22 2020 Akos Balla <akos.balla@sirc.hu> - 0.6.2-2
- support Fedora Silverblue
- add motd/profile files

* Sat Oct 31 2020 Georg Sauthoff <mail@gms.tf> - 0.6.2-1
- check whether key is included

* Thu May 28 2020 Georg Sauthoff <mail@gms.tf> - 0.6.1-2
- add example dracut config

* Thu May 28 2020 Georg Sauthoff <mail@gms.tf> - 0.6.1-1
- eliminate dracut module dependencies
- don't auto-include networkd configurations, anymore
- auto-include sshd executable dependencies

* Sat Jan 26 2019 Georg Sauthoff <mail@gms.tf> - 0.4-1
- initial packaging
