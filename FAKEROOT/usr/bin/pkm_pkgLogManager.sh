#!/bin/bash
logFile=/var/log/pkm/pkgLog
pipe=/root/LFS_Pkm/FAKEROOT/var/run/pkm/pipes/pkgLog
while read -r line; do
    echo "Reading: "$line >> $logFile
done < <(tail -f $pipe)
