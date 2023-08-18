# Debian packaging

This folder include necessary code to build your own .deb package. This
packaging code is currently maintained by Enneamer
<[enneamer@enneamer.is](mailto:enneamer@enneamer.is)>.

## Step to build the Debian/Ubuntu package

1. (Optional) In case you do not want to install Debian/Ubuntu 
   development packages in your host system, you may choose to use
   Docker. Assuming you have installed Docker on your system, launch a
   Docker container with `docker run -i -t -w /root debian:stable-slim`
2. Install `git-buildpackage`: `apt-get update && apt-get install git-buildpackage`
3. Clone the repository: `gbp clone https://github.com/gsauthof/dracut-sshd.git`
4. Enter the folder: `cd dracut-sshd`
5. Build the package: `gbp buildpackage --git-upstream-tree=branch --no-sign`
6. The debian packages and relavant files should be in the parent folder.

For more information regarding proper Debian packaging, please refer to
[Debian wiki page for packaging with Git][debian-package-git] and
[Git-buildpackage official website][git-buildpackage].
