#!/bin/bash
#
# Mofified from: https://github.com/szepeviktor/debian-server-tools/blob/master/debian-resizefs.sh
# Reduce root lvm volume size during boot.
#

l_f=false

while getopts ':l:' OPTION; do
    case "$OPTION" in
        l)
            l_f=true
            REDUCE_SIZE="$OPTARG"
            ;;
        ?)
            echo "script usage: $(basename $0) -l reduce_size"
            exit 1
            ;;
    esac
done

if ! $l_f ; then
    echo "error: option -l is required"
    echo "script usage: $(basename $0) -l reduce_size"
    exit 1
fi


# Check current filesystem type
ROOT_FS_TYPE="$(sed -n -e 's|^/dev/\S\+ / \(ext4\) .*$|\1|p' /proc/mounts)"
test "$ROOT_FS_TYPE" == ext4 || exit 100

# Get volumn group name of root. xargs to trim space
ROOT_VG=$(lvs -S lv_name=root --no-heading -o vg_name | xargs)

# Copy tools and libs to initrd
cat > /etc/initramfs-tools/hooks/lvreduce <<"EOF"
#!/bin/sh

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions
copy_exec /sbin/findfs /sbin
copy_exec /sbin/e2fsck /sbin
copy_exec /sbin/resize2fs /sbin
copy_exec /sbin/lvreduce /sbin
copy_exec /sbin/lvcreate /sbin
copy_exec /sbin/mke2fs /sbin
copy_exec /usr/bin/yes /usr/bin

# libs. check which lib is needed using ldd /sbin/lvcreate
copy_exec /lib/x86_64-linux-gnu/libudev.so.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libdl.so.2 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libblkid.so.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libdevmapper-event.so.1.02.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libdevmapper.so.1.02.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libreadline.so.5 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/librt.so.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libpthread.so.0 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libuuid.so.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libselinux.so.1 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libm.so.6 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libtinfo.so.5 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libpcre.so.3 /lib/x86_64-linux-gnu/
copy_exec /lib/x86_64-linux-gnu/libext2fs.so.2 /lib/x86_64-linux-gnu
copy_exec /lib/x86_64-linux-gnu/libcom_err.so.2 /lib/x86_64-linux-gnu
copy_exec /lib/x86_64-linux-gnu/libe2p.so.2 /lib/x86_64-linux-gnu
copy_exec /lib64/ld-linux-x86-64.so.2 /lib64/

EOF

chmod +x /etc/initramfs-tools/hooks/lvreduce

# Execute lvreduce before mounting root filesystem
cat > /etc/initramfs-tools/scripts/init-premount/lvreduce <<"EOF"
#!/bin/sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin
export PATH

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# New size of backups
REDUCE_SIZE={{ REDUCE_SIZE }}

# Convert root from possible UUID to device name
echo "root=${ROOT}"
ROOT_DEVICE="$(findfs "$ROOT")"
echo "root device name is ${ROOT_DEVICE}"

# Make sure LVM volumes are activated
vgchange -a y

# Check root filesystem
e2fsck -y -v -f "$ROOT_DEVICE"

# Resize file system to minimum, reduce lv size, then resize file system to lv size
# debug-flag 8 means debug moving the inode table
resize2fs -d 8 -M "$ROOT_DEVICE"
yes y | lvreduce --size -"$REDUCE_SIZE" "$ROOT_DEVICE"
resize2fs -d 8 "$ROOT_DEVICE"
EOF

sed -i "s/{{ ROOT_VG }}/$ROOT_VG/g" /etc/initramfs-tools/scripts/init-premount/lvreduce
sed -i "s/{{ REDUCE_SIZE }}/$REDUCE_SIZE/g" /etc/initramfs-tools/scripts/init-premount/lvreduce

chmod +x /etc/initramfs-tools/scripts/init-premount/lvreduce

# Regenerate initrd
update-initramfs -u

# Remove files
rm -f /etc/initramfs-tools/hooks/lvreduce /etc/initramfs-tools/scripts/init-premount/lvreduce

# reboot
