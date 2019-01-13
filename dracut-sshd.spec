Name:       {{{ git_dir_name }}}
Version:    {{{ git_dir_version }}}
Release:    1%{?dist}
Summary:    Add sshd to your initramfs

License:    GPLv3+
VCS:        {{{ git_dir_vcs }}}

Source:     {{{ git_dir_pack }}}
BuildArch:  noarch
%define debug_package %{nil}
Requires:   dracut-network

%description
Add sshd to your initramfs

%prep
{{{ git_dir_setup_macro }}}

%build
# nothing to do here

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/lib/dracut/modules.d/
mv 46sshd %{buildroot}/usr/lib/dracut/modules.d/

%clean
rm -rf %{buildroot}

%files
%attr(755, root, root) /usr/lib/dracut/modules.d/46sshd/module-setup.sh
%attr(644, root, root) /usr/lib/dracut/modules.d/46sshd/sshd.service
%attr(644, root, root) %config(noreplace) /usr/lib/dracut/modules.d/46sshd/sshd_config

%changelog

