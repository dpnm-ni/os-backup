#!/bin/bash
#
# backup root filesystem with fsarchiver
# More detail: http://www.system-rescue-cd.org/lvm-guide-en/Making-consistent-backups-with-LVM/
#

set -e

# only run as root
if [ "$(id -u)" != '0' ]
then
    echo "this script has to be run as root"
    exit 1
fi

#
# Get all the variable first
#

backup_f=false
restore_f=false
name_f=false
list_backup_f=false
force_f=false

ORIG_VOL='root' # name of the logical volume to backup
SNAP_VOL='root_snap' # name of the snapshot to create
STOR_VOL='stor_vol' # name of the volume to store result
STOR_SIZE='30G' # space for the storage volume to store backups
FSAOPTS='-z5 -j3' # options to pass to fsarchiver

# get volumn group name of root. xargs to trim space
VOL_GROUP=$(lvs -S lv_name=${ORIG_VOL} --no-heading -o vg_name | xargs)

print_usage () {
    echo "script usage: $(basename $0) [-b] [-r] [-l] [-f] [-n backup_name]"
    echo "-b: create new backup with name backup_name"
    echo "-r: restore backup_name"
    echo "-l: list all backups"
    echo "-f: force remove existing snapshot volume if exist"
}

while getopts ':brlfn:' OPTION; do
    case "$OPTION" in
        b)
            backup_f=true
            ;;
        r)
            restore_f=true
            ;;
        l)
            list_backup_f=true
            ;;
        f)
            force_f=true
            ;;
        n)
            name_f=true
            BACKNAME="$OPTARG" # name of the archive
            ;;
        ?)
            print_usage
            exit
            ;;
    esac
done

if [[ $list_backup_f == false && \
    ( $name_f == false || \
    (( $backup_f == true && $restore_f == true ) || \
    ( $backup_f == false && $restore_f == false )) ) ]] ; then
    echo "error: -l is required; or -n and one (and only one) of -b or -r are required"
    print_usage
    exit 1
fi

#
# main script
#

# check and install fsarchiver if not existed yet
if ! [ -e "/usr/sbin/fsarchiver" ] ; then
    echo "fsarchiver not installed yet. attemp to install"
    apt update && apt install -y fsarchiver
fi

# check that the storage vol exist
if ! [ -e "/dev/${VOL_GROUP}/${STOR_VOL}" ]
then
    echo "storage vol does not exist. attemp to create one ..."
    lvcreate -L $STOR_SIZE -n $STOR_VOL $VOL_GROUP

    # Created volume somehow might has file system error :(, thus filesystem need to be re-created
    mke2fs -t ext4 /dev/${VOL_GROUP}/${STOR_VOL}
    e2fsck -y -v -f /dev/${VOL_GROUP}/${STOR_VOL}
fi

# mount the storage volume
mkdir -p /${STOR_VOL}
# this check is dirty...
if ! grep -qs "${STOR_VOL} /${STOR_VOL}" /proc/mounts; then
    mount -t ext4 /dev/${VOL_GROUP}/${STOR_VOL} /${STOR_VOL}
fi

if $list_backup_f ; then
    echo "available backups:"
    echo "------------------"
    ls -h /${STOR_VOL} | grep ".fsa" | sed 's/\.[^.]*$//'
    exit
fi

# remove the snapshot volume if exist
if [ -e "/dev/${VOL_GROUP}/${SNAP_VOL}" ]
then
    echo "the lvm snapshot already exists"
    if ! $force_f ; then
        echo "remove the lvm snapshot manually first."
        exit 1
    else
        echo "force remove the existing snapshot"
        lvremove -f /dev/${VOL_GROUP}/${SNAP_VOL}
    fi
fi

# create the lvm snapshot
lvcreate -l 100%FREE -s -n ${SNAP_VOL} /dev/${VOL_GROUP}/${ORIG_VOL}

if $backup_f ; then
    if ! $force_f ; then
        # create backup file and checksum. fsarchiver will exit if same backupname exist
        fsarchiver savefs ${FSAOPTS} /${STOR_VOL}/${BACKNAME}.fsa /dev/${VOL_GROUP}/${SNAP_VOL}
    else
        fsarchiver savefs -o ${FSAOPTS} /${STOR_VOL}/${BACKNAME}.fsa /dev/${VOL_GROUP}/${SNAP_VOL}
    fi
    md5sum /${STOR_VOL}/${BACKNAME}.fsa > /${STOR_VOL}/${BACKNAME}.md5
    # remove the snapshot vol
    lvremove -f /dev/${VOL_GROUP}/${SNAP_VOL}
fi

if $restore_f ; then
    # restore to snap vol then merge to origin vol
    fsarchiver restfs ${FSAOPTS} /${STOR_VOL}/${BACKNAME}.fsa id=0,dest=/dev/${VOL_GROUP}/${SNAP_VOL}
    lvconvert --merge /dev/${VOL_GROUP}/${SNAP_VOL}
fi
