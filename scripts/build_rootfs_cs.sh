#!/bin/sh
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
		-d|--disable-services)
            services="$2"; shift 2;;
		-o|--output)
			dst_file="$2"; shift 2;;
		-f|--files)
			files="$2"; shift 2;;
		-m|--metadata)
			metadata=$(basename "$2")
			metadata_dir=$(dirname "$2")
			shift 2;;
		--help)
			usage;;
		--)
			shift; break;;
	esac
done
if [ $# -ne 1 ]; then
	usage
fi
src_tar=$1
dir=/tmp/build.$$
files_dir=files/
instroot=$dir/rootfs
unpack() {
	mkdir -p $instroot
	 (cd $instroot && tar -xz) < "$src_tar"
}
pack() {
	echo Pack rootfs
	if test -n "$metadata"; then
		(cd "$dir" && tar -cz --numeric-owner --owner=0 --group=0 --sort=name -- *  ) > "$dst_file"
	else
		(cd "$dir"/rootfs && tar -cz --numeric-owner --owner=0 --group=0 --sort=name -- * ) > "$dst_file"
	fi
}
disable_root() {
	sed -i -e 's/^root::/root:*:/' "$instroot"/etc/shadow
}
add_file() {
    file=$1
    src_dir=$2
    dst_dir=$3
    src=$src_dir/$file
    dst=$dst_dir/$file
    if test -d "$src"; then
	test -d "$dst" || mkdir -p "$dst"
    elif test -f "$src"; then
	cp "$src" "$dst"
	foo=$(dirname "$file")
	if [ "$foo" = "./etc/init.d" ]; then
	    echo Enabling "$file"
	    set +e
	    env IPKG_INSTROOT=$instroot sh $instroot/etc/rc.common "$dst" enable
	    set -e
	fi
    fi
}
add_files() {
	src_dir=$1
	dst_dir=$2
	for f in $(cd "$src_dir" && find . ); do
		add_file "$f" "$src_dir" "$dst_dir"
	done
}
disable_services() {
    local services="$1"
    for service in $services; do
        echo Disabling "$service"
        env IPKG_INSTROOT=$instroot sh $instroot/etc/rc.common $instroot/etc/init.d/"$service" disable
    done
}
clean_up() {
	rm -rf "$dir"
}
unpack
disable_root
if test -n "$metadata"; then
	add_file "$metadata" "$metadata_dir" $dir
fi
add_files templates/ $dir/templates/
disable_services "$services"
add_files $files_dir $instroot
if test -n "$files"; then
	add_files "$files" $instroot
fi
pack
clean_up
