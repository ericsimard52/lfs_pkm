#!/bin/bash
logFile=/var/log/pkm/stdLog
pipe=/root/LFS_Pkm/FAKEROOT/var/run/pkm/pipes/stdLog
if [ ! -f $logFile ]; then
    echo "$logFile missing, touching."
    touch $logFile
fi
while read -r line; do
    echo "Reading: "$line >> $logFile
done < <(tail -f $pipe) &

