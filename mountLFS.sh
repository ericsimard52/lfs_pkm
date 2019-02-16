#!/bin/bash
declare -a PARTITIONNAME=('root' 'swap')
declare -a PARTITIONMOUNT=('/')
declare -a PARTITIONDEV=('/dev/sda7' '/dev/sda2')
declare -a PARTITIONFS=('ext4')
declare LFS=/mnt/lfs

echo "Checking mountpoint."
if [ ! -d $LFS ]; then
    echo "ERROR|Mount point $LFS does not exist. Creating."
    sudo mkdir -pv $LFS
    [ $? -gt 0 ] && echo "Error creating $LFS." && exit 1
fi
echo "Mounting partitions."
x=0
pl=${#PARTITIONNAME[@]}
echo "Got $pl partition to mount."
while [ $x -lt $pl ]; do
    pn=${PARTITIONNAME[$x]}
    pm=${PARTITIONMOUNT[$x]}
    pd=${PARTITIONDEV[$x]}
    pf=${PARTITIONFS[$x]}

    if [[ "$pn" = "swap" ]]; then
        if [[ `grep /dev/ < <(sudo swapon -s) |wc -l` < 1 ]]; then
            echo "Found swap partition, Ativating."
            sudo /sbin/swapon -v $pd
            [ $? -gt 0 ] && echo "Error activating swap" && exit 1
            break
        else
            echo "Swap already active, skipping."
            break
        fi
    fi

    if [ ! -d $LFS$pm ]; then
        echo "$LFS$pm does not exists, creating."
        sudo mkdir -pv $LFS$pm
        [ $? -gt 0 ] && echo "$LFS$pm does not exists and unable to create." && exit 1
    fi
    echo "Check if $pd mounted on $pm"
    if [[ `grep "$pd on $pm" < <(mount) | wc -l` < 1 ]]; then
        echo "Mounting $pd on $pm"
        sudo mount -v -t $pf $pd $LFS$pm
        [ $? -gt 0 ] && echo "Unable to mount $pd on $pm" && exit 1
        ((x++))
    else
        echo "$pd already mounted on $pm, skipping."
        ((x++))
    fi
done

declare -a dl_=($LFS/dev $LFS/proc $LFS/sys $LFS/run)

for d_ in ${dl_[@]}; do
    echo "Creating directory $d_."
    sudo mkdir -pv $d_
    [ $? -gt 0 ] && echo "Error creating directory $d_."
done

if [ ! -c $LFS/dev/console ]; then
    echo "Creating initial Device Nodes console"
    sudo mknod -m 600 $LFS/dev/console c 5 1
    [ $? -gt 0 ] && echo "Error creating console"
fi

if [ ! -c $LFS/dev/null ]; then
    echo "Creating null device."
    sudo mknod -m 666 $LFS/dev/null c 1 3
    [ $? -gt 0 ] && echo "Error creating null"
fi


findmnt $LFS/dev
if [ $? -gt 0 ]; then
    echo "Binding host /dev to lfs /dev"
    sudo mount -v --bind /dev $LFS/dev
    [ $? -gt 0 ] && echo "Unable to bind dev between host and lfs" t && exit 1
fi


findmnt $LFS/dev/pts
if [ $? -gt 0 ]; then
    echo "Mounting $LFS/dev/pts"
    sudo mount -vt devpts devpts $LFS/dev/pts -o gid=5,mode=620
    [ $? -gt 0 ] && echo "Error mount devpts" && exit 1
fi
findmnt $LFS/proc
if [ $? -gt 0 ]; then
    echo "Mounting $LFS/proc"
    sudo mount -vt proc proc $LFS/proc
    [ $? -gt 0 ] && echo "Error mount proc" && exit 1
fi

findmnt $LFS/sys
if [ $? -gt 0 ]; then
    sudo mount -vt sysfs sysfs $LFS/sys
    [ $? -gt 0 ] && echo "Error mount sys" && exit 1
fi

findmnt $LFS/run
if [ $? -gt 0 ]; then
    sudo mount -vt tmpfs tmpfs $LFS/run
    [ $? -gt 0 ] && echo "Error mount run" && exit 1
fi

if [ -h $LFS/dev/shm ]; then
    sudo mkdir -pv $LFS/$(readlink $LFS/dev/shm)
fi
echo "All seems good."
exit 0


