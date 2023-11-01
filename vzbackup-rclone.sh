#!/bin/bash
# ./vzbackup-rclone.sh rehydrate YYYY/MM/DD file_name_encrypted.bin

############ /START CONFIG
DRIVE_NAME="xxx"
BUKKET_NAME="yyy"
DUMP_DIR="/var/lib/vz/dump" # Set this to where your vzdump files are stored
MAX_AGE=3                  # This is the age in days to keep local backup copies. Local backups older than this are deleted.
MAX_CLOUD_AGE=30            # This is the age in days to keep cloud backup copies. Cloud backups older than this are deleted
############ /END CONFIG

_bdir="$DUMP_DIR"
RCLONE_ROOT="$DUMP_DIR"
TIME_PATH="$(date +%Y-%m-%d)"
RCLONE_DIR="$RCLONE_ROOT/$TIME_PATH"
COMMAND=${1}
rehydrate=${2} #enter the date you want to rehydrate in the following format: YYYY/MM/DD
if [ ! -z "${3}" ]; then
    CMDARCHIVE=$(echo "/${3}" | sed -e 's/\(.bin\)*$//g')
fi
if [ -z ${TARGET+x} ]; then
    tarfile=${TARFILE}
else
    tarfile=${TARGET}
fi
exten=${tarfile#*.}
filename=${tarfile%.*.*}

if [[ ${COMMAND} == 'rehydrate' ]]; then
    #echo "Please enter the date you want to rehydrate in the following format: YYYY/MM/DD"
    #echo "For example, today would be: $TIME_PATH"
    #read -p 'Rehydrate Date => ' rehydrate
    rclone --config /root/.config/rclone/rclone.conf \
        --drive-chunk-size=32M copy $DRIVE_NAME:/$BUKKET_NAME/$HOSTNAME/$rehydrate$CMDARCHIVE $DUMP_DIR \
        -v --stats=60s --transfers=16 --checkers=16
fi

if [[ ${COMMAND} == 'job-start' ]]; then
    echo "Deleting backups older than $MAX_AGE days."
    find $DUMP_DIR -type f -mtime +$MAX_AGE -exec /bin/rm -f {} \;
fi

if [[ ${COMMAND} == 'backup-end' ]]; then
    echo "Backing up $tarfile to remote storage"
    echo "rcloning $RCLONE_DIR"

    rclone --config /root/.config/rclone/rclone.conf \
        --drive-chunk-size=32M copy $tarfile $DRIVE_NAME:/$BUKKET_NAME/$HOSTNAME/$TIME_PATH \
        -v --stats=60s --transfers=16 --checkers=16
fi

if [[ ${COMMAND} == 'job-end' || ${COMMAND} == 'job-abort' ]]; then
    echo "Backing up main PVE configs"
    _tdir=${TMP_DIR:-/var/tmp}
    _tdir=$(mktemp -d $_tdir/proxmox-XXXXXXXX)
    function clean_up {
        echo "Cleaning up"
        rm -rf $_tdir
    }
    trap clean_up EXIT
    _now=$(date +%Y-%m-%d.%H.%M.%S)
    _HOSTNAME=$(hostname -f)
    _filename1="$_tdir/proxmoxetc.$_now.tar"
    _filename2="$_tdir/proxmoxpve.$_now.tar"
    _filename3="$_tdir/proxmoxroot.$_now.tar"
    _filename4="$_tdir/proxmox_backup_"$_HOSTNAME"_"$_now".tar.gz"

    echo "Tar files"
    # copy key system files
    tar --warning='no-file-ignored' -cPf "$_filename1" /etc/.
    tar --warning='no-file-ignored' -cPf "$_filename2" /var/lib/pve-cluster/.
    tar --warning='no-file-ignored' -cPf "$_filename3" /root/.

    echo "Compressing files"
    # archive the copied system files
    tar -cvzPf "$_filename4" $_tdir/*.tar

    # copy config archive to backup folder
    cp -v $_filename4 $_bdir/

    echo "rcloning $_filename4"

    rclone --config /root/.config/rclone/rclone.conf \
        --drive-chunk-size=32M move $_filename4 $DRIVE_NAME:/$BUKKET_NAME/$HOSTNAME/$TIME_PATH \
        -v --stats=60s --transfers=16 --checkers=16

    rclone --config /root/.config/rclone/rclone.conf \
        delete --min-age ${MAX_CLOUD_AGE}d $DRIVE_NAME:/$BUKKET_NAME/$HOSTNAME/
fi
