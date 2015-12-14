#!/usr/bin/env bash

OUTPUT=/tmp/`date +%Y-%m-%d_%H:%m:%S`-platform-feedback
echo -n "Writing system status to \"${OUTPUT}\"... "
mkdir -p ${OUTPUT}

df -h > ${OUTPUT}/disk-free-space.txt
df -i > ${OUTPUT}/disk-free-inodes.txt
sudo dmesg > ${OUTPUT}/dmesg.txt

if [[ -f /data/dokku/.ssh/authorized_keys ]]; then
ssh-keygen -l -f /data/dokku/.ssh/authorized_keys > ${OUTPUT}/dokku-ssh-keys.log
fi

if [[ -x $(which systemctl) ]]; then
    sudo systemctl > ${OUTPUT}/systemd-service-list.txt
    sudo systemctl | awk '/fail/ {print $1}' | xargs -n 1 -i sudo systemctl status {} > ${OUTPUT}/systemd-service-status-failed.txt
fi

if [[ -x $(which journalctl) ]]; then
    sudo journalctl -b > ${OUTPUT}/current.log
    sudo journalctl -b "-1" > ${OUTPUT}/previous.log
fi

if [[ -x $(which docker) ]]; then
    docker ps -a > ${OUTPUT}/docker-ps-a.txt
    docker images > ${OUTPUT}/docker-images.txt
fi

if [[ -x $(which zfs) ]]; then
    sudo zpool list > ${OUTPUT}/zpool-list.txt
    sudo zpool status  > ${OUTPUT}/zpool-status.txt
    sudo zpool get all  > ${OUTPUT}/zpool-get-all.txt
    sudo zpool history  > ${OUTPUT}/zpool-history.txt
    sudo zpool events  > ${OUTPUT}/zpool-events.txt
    sudo zfs list  > ${OUTPUT}/zfs-list.txt
    sudo zfs get all  > ${OUTPUT}/zfs-get-all.txt
fi

tar cfz ${OUTPUT}.tgz ${OUTPUT} && rm -rf ${OUTPUT}
echo -e "\n\n\nPLEASE SEND '${OUTPUT}.tgz' TO YOUR FRIENDLY SUPPORT TEAM. THANK YOU\n"

# TODO: send it and then clean up