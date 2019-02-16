#!/bin/bash
declare -a lfsMounts=()
for m in `findmnt /mnt/lfs -R --raw -o TARGET -n`; do
    lfsMounts+=("$m")
done
t=${#lfsMounts[@]}
((t--))
while [ ! $t -eq -1 ]; do
    echo "Umount ${lfsMounts[$t]}."
    sudo umount -v ${lfsMounts[$t]}
    ((t--))
done

