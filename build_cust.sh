#!/bin/sh
set -e
export LC_ALL=C
super=fakeroot
rootfs="$1"
if [ ! -s "$rootfs" ]; then
	echo "Invalid file. Abort."
	exit 1
fi
usage() {
	echo "Usage: $0 <rootfs tarball> <lxd|plain> "
	exit 1
}
type=$2
if [ "$type" != plain ] && [ "$type" != lxd ]; then
	usage
fi
dir=$(mktemp -d)
if [ -d "$dir" ]; then
	if tar xf "$rootfs" ./etc/openwrt_release -O >"$dir"/openwrt_release; then
		ver="$(grep DISTRIB_RELEASE "$dir"/openwrt_release | sed -e "s/.*='\(.*\)'/\1/")"
		dist="$(grep DISTRIB_ID "$dir"/openwrt_release | sed -e "s/.*='\(.*\)'/\1/")"
		revision="$(grep DISTRIB_REVISION "$dir"/openwrt_release | sed -e "s/.*='\(.*\)'/\1/")"
		arch_lxd="$(grep DISTRIB_ARCH "$dir"/openwrt_release | sed -e "s/.*='\(.*\)'/\1/")"
		desc="$(grep DISTRIB_DESCRIPTION "$dir"/openwrt_release | sed -e "s/.*='\(.*\)'/\1/")"
		rm -rf "$dir"
		if [ ! "$arch_lxd" ] || [ ! "$dist" ] || [ ! "$ver" ] || [ ! "$revision" ]; then
			echo "Possible an invalid OpenWrt rootfs tarball. Failed."
			exit 1
		fi
	else
		echo "Invalid tarball. Abort."
		rm -rf "$dir"
		exit 1
	fi
else
	echo "Failed to make temp dir. Abort."
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
	mkdir -p bin
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
