#!/bin/sh
set -e
export LC_ALL=C
super=fakeroot
ver=$(basename "$1" | cut -d'-' -f 2)
dist=$(basename "$1" | cut -d'-' -f 1)
type=$2
usage() {
	echo "Usage: $0 <rootfs tarball> <lxd|plain> "
	exit 1
}
if [ "$type" != plain ] && [ "$type" != lxd ]; then
	usage
	exit 1
fi
revision=$(basename "$1" | cut -d'-' -f 3-4)
rootfs="$1"
arch_lxd="$(tar xf "$rootfs" ./etc/openwrt_release -O | grep DISTRIB_ARCH | sed -e "s/.*='\(.*\)'/\1/")"
if [ ! "$arch_lxd" ]; then
	echo "Unknown CPU arch. Possible an invalid OpenWrt rootfs tarball. Failed."
	exit 1
fi
tarball=bin/${dist}-${ver}-${revision}-${arch_lxd}-${type}.tar.gz
metadata=bin/metadata.yaml
build_tarball() {
	local opts=""
	if [ "${type}" = lxd ]; then
		opts="$opts -m $metadata"
	fi
	local cmd=""
	cmd="scripts/build_rootfs_cs.sh"
	if [ "$(id -u)" != 0 ]; then
		case "$super" in
			sudo)
				cmd="sudo $cmd"
				;;
			fakeroot)
				cmd="fakeroot $cmd"
				;;
			*)
				echo "You have to sudo or use fakeroot."
				exit 1
				;;
		esac
	fi
	$cmd "$rootfs" $opts -o "$tarball" --disable-services="sysfixtime sysntpd led urngd"
}
build_metadata() {
	local desc=""
	desc="$(tar xf "$rootfs" ./etc/openwrt_release -O | grep DISTRIB_DESCRIPTION | sed -e "s/.*='\(.*\)'/\1/")"
	if [ ! -d bin ]; then
		mkdir bin
	fi
	cat >$metadata <<EOF
architecture: "$arch_lxd"
creation_date: $(date +%s)
properties:
 architecture: "$arch_lxd"
 description: "$desc"
 os: "$dist"
 release: "$ver"
templates:
EOF
}
build_metadata
build_tarball
echo "Tarball built: $tarball"
