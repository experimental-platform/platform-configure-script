#!/usr/bin/env bash

OUTPUT=/tmp/`date +%Y-%m-%d_%H:%m:%S`-platform-feedback
echo -n "Writing system status to \"${OUTPUT}\"... "
mkdir -p ${OUTPUT}
sudo journalctl -b > ${OUTPUT}/current.log
sudo journalctl -b "-1" > ${OUTPUT}/previous.log
docker ps -a > ${OUTPUT}/docker-ps-a.txt
docker images > ${OUTPUT}/docker-images.txt
sudo systemctl > ${OUTPUT}/systemd-service-list.txt
sudo systemctl | awk '/fail/ {print $1}' | xargs -n 1 -i sudo systemctl status {} > ${OUTPUT}/systemd-service-status-failed.txt
echo "DONE."
# TODO: tar it up, send it and then clean up