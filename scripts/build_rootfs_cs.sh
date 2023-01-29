#!/bin/bash
set -e
usage() {
	echo "Usage: $0  [-d|--disable-services <services>] [-o|--output <dst file>][-f|--files <files>] [-m|--metadata <metadata.yaml>]  <src tar>"
	exit 1
}
dst_file=/dev/stdout
files=
services=
metadata=
metadata_dir=
temp=$(getopt -o "d:o:f:m:" -l "disable-services:,output:,files:,metadata:,help" -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-d | --disable-services)
			services="$2"
			shift 2
			;;
		-o | --output)
			dst_file="$2"
			shift 2
			;;
		-f | --files)
			files="$2"
			shift 2
			;;
		-m | --metadata)
			metadata=$(basename "$2")
			metadata_dir=$(dirname "$2")
			shift 2
			;;
		--help)
			usage
			;;
		--)
			shift
			break
			;;
	esac
done
if [ $# -ne 1 ]; then
	usage
fi
src_tar=$1
dir=$(mktemp -d)
if [ ! -d "$dir" ]; then
	echo "Failed to make temp dir. Abort."
	exit 1
fi
files_dir=files/
instroot="$dir"/rootfs
unpack() {
	mkdir -p "$instroot"
	(cd "$instroot" && tar -xz) <"$src_tar"
}
pack() {
	echo Pack rootfs
	if [ -n "$metadata" ]; then
		local TARGET_DIR="$dir"
	else
		local TARGET_DIR="$dir"/rootfs
	fi
	tar -cp --sort=name -C "$TARGET_DIR" . | gzip -9n >"$dst_file"
}
disable_root_and_jail() {
	sed -i -e 's/^root::/root:*:/' "$instroot"/etc/shadow
	#FIXME
	#Disable process isolation for dnsmasq
	if [ -x "$instroot"/etc/init.d/dnsmasq ]; then
		sed -i -e '/procd_add_jail/s/^/#/' "$instroot"/etc/init.d/dnsmasq
	fi
}
add_file() {
	file=$1
	src_dir=$2
	dst_dir=$3
	src=$src_dir/$file
	dst=$dst_dir/$file
	if [ -d "$src" ]; then
		if [ ! -d "$dst" ]; then
			mkdir -p "$dst"
		fi
	elif [ -f "$src" ]; then
		cp "$src" "$dst"
		foo=$(dirname "$file")
		if [ "$foo" = "./etc/init.d" ]; then
			echo Enabling "$file"
			set +e
			env IPKG_INSTROOT="$instroot" sh "$instroot"/etc/rc.common "$dst" enable
			set -e
		fi
	fi
}
add_files() {
	src_dir=$1
	dst_dir=$2
	for f in $(cd "$src_dir" && find .); do
		add_file "$f" "$src_dir" "$dst_dir"
	done
}
disable_services() {
	local services="$1"
	for service in $services; do
		local init_script="$instroot"/etc/init.d/"$service"
		if [ -x "$init_script" ]; then
			echo Disabling "$service"
			env IPKG_INSTROOT="$instroot" sh "$instroot"/etc/rc.common "$init_script" disable
		else
			echo "$service" not found. Skip.
		fi
	done
}
clean_up() {
	rm -rf "$dir"
}
unpack
disable_root_and_jail
if [ -n "$metadata" ]; then
	add_file "$metadata" "$metadata_dir" "$dir"
fi
add_files templates/ "$dir"/templates/
disable_services "$services"
add_files $files_dir "$instroot"
if [ -n "$files" ]; then
	add_files "$files" "$instroot"
fi
pack
clean_up
