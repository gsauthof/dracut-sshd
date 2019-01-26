Name:       {{{ git_dir_name }}}
Version:    {{{ git_dir_version }}}
Release:    1%{?dist}
Summary:    Provide SSH access to initramfs early user space
URL:        https://github.com/gsauthof
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
%config(noreplace) /usr/lib/dracut/modules.d/46sshd/sshd_config
%doc README.md
%doc example/20-wired.network

%changelog
* Sat Jan 26 2019 Georg Sauthoff <mail@gms.tf> - 0.4-1
- initial packaging
