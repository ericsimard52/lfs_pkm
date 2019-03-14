#!/bin/bash
LFS=/mnt/lfs
BASE=/home/tech/Git/lfs_pkm/FAKEROOT
echo "updating all but etc/pkm.conf"
pushd $BASE/etc/pkm >/dev/null 2>&1
for i in *; do
    [ -d $i ] && sudo cp -vfr $i $LFS/etc/pkm/
done
popd >/dev/null 2>&1
echo "Updating pkm.sh"
pushd $BASE/usr/bin >/dev/null 2>&1
sudo cp -vf pkm.sh $LFS/usr/bin/
popd >/dev/null 2>&1
echo "Updating owner:group"
sudo chown root:root -c $LFS/{etc,usr}
echo "Done."
