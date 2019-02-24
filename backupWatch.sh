#!/bin/bash
## This script depends on inotify-tools
## TODO, fix to handle multiple partition backup.
[ $EUID -gt 0 ] && echo "Run this as root" && exit 1
declare LFS="/mnt/lfs"
declare backupWatch=$LFS/var/log/pkm/
declare nFile fName backupName bakDest
declare DEBUG=0 # set to 1 to have tar verbose.
while true; do
    nFile=`inotifywait -e create $backupWatch`
    fName=`rev < <(echo $nFile) |cut -d' ' -f1 | rev`
    echo "fname: $fName"
    if [[ "$fName" == "backup" ]]; then
        backupName=`cat $backupWatch$fName`
        echo "Requested backup name: $backupName"
        bakDest=/root/$backupName.tar.gz
        ## This could be done better.
        [ $DEBUG -gt 0 ] && tar -cvpzf $bakDest --exclude=$bakDest --one-file-system $LFS || tar -cpzf $bakDest --exclude=$bakDest --one-file-system $LFS
        rm -v $backupWatch$fName
        unset nFile fName backupName bakDest
        echo "Backup done, backup location: $bakDest. Watching again."
    elif [[ "$fName" == "endWatch" ]]; then
        echo "Done watching for bacup request"
        break
    else
        echo "New file create but not what I was looking for, continue watching."
    fi
done
exit 0
