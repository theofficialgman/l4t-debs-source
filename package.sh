# run this script from the folder (working directory) of the package that you would like to build
# a package with the name formatted as "package_version_arch.deb" will be created one folder up from the working directory
dpkg-deb --root-owner-group -b . ../