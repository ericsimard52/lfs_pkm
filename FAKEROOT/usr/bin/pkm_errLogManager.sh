#!/bin/bash
pipe=/root/LFS_Pkm/FAKEROOT/var/run/pkm/pipes/errLog
errlogFile=/var/log/pkm/errLog
while read -r line; do
    echo "Reading: "$line >> $errlogFile
done < <(tail -f $pipe)
