#!/bin/bash
logFile=/var/log/pkm/impLog
pipe=/root/LFS_Pkm/FAKEROOT/var/run/pkm/pipes/impLog
while read -r line; do
    echo "Reading: "$line >> $logFile
done < <(tail -f $pipe)
