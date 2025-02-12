#!/bin/bash

# Install mdadm
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mdadm

# Create RAID 1
sudo mdadm --create --verbose /dev/md0 --level=1 --name=backups --raid-devices=2 /dev/xvdf /dev/xvdg --force --run

# Await RAID sync
while [ "$(cat /proc/mdstat | grep -cE 'resync|recover')" -gt 0 ]; do
    echo "Waiting RAID sync..."
    sleep 5
done
mkfs.ext4 /dev/md0
mkdir -p /mnt/raid1
mount /dev/md0 /mnt/raid1
UUID=$(blkid -s UUID -o value /dev/md0)
echo "UUID=$UUID  /mnt/raid1  ext4  defaults,nofail  0  0" >> /etc/fstab
mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
update-initramfs -u

echo "RAID 1 setup completed!"




