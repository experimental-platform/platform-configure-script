#!/bin/bash
set -e

# Copyright 2015 Protonet GmbH
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

DOCKER=$(which docker)
REGISTRY="experimentalplatform"
CONTAINER_NAME="configure"
CHANNEL_FILE=/etc/protonet/system/channel
UPDATE_ENGINE_CONFIG=/etc/coreos/update.conf
IMAGE_STATE_DIR=/etc/protonet/system/images

PLATFORM_INSTALL_REBOOT=${PLATFORM_INSTALL_REBOOT:=false}
PLATFORM_INSTALL_RELOAD=${PLATFORM_INSTALL_RELOAD:=false}
PLATFORM_INSTALL_OSUPDATE=${PLATFORM_INSTALL_OSUPDATE:=false}
PLATFORM_INSTALL_DEBUG=${PLATFORM_INSTALL_DEBUG:=false}

PROTONET_PUBKEY="-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5CfJQVP2yJlcMu/3/RxD
KnOvcxD40VWsDiUn/FDXlcgQWpg/xH2a7LD9bpD4c3+jWtUst+I7ZhL11YiyfQDr
Afw9m11RiHtl+fvJfLg8PwuQ25jc5Cf/hLn+NpnFxL4vlifNWljIoIh17j3KE0hj
jd/V7435gkIm0eIvTiebn4cposzh74XrlOnsGyTTyPJ4IMcnS3zYdOIAeTKoSMea
rUIsXC8jYMQtua8q96eqM3bPsvFLBWRRQoTfRtVSfydNbZp+i1SixVKo4oDz9UmF
fNLAJRPgRI+pXV0O6MdmPtKu5dQNkVGAYm7RWbxZctGxsOArXE43OjqE6kGLVabw
7QIDAQAB
-----END PUBLIC KEY-----"

function is_update_key_protonet() {
	key_path="/usr/share/update_engine/update-payload-key.pub.pem"
  current_digest=$(cat "$key_path" | /usr/bin/sha1sum | cut -f1 -d ' ')
	protonet_digest=$(echo "$PROTONET_PUBKEY" | /usr/bin/sha1sum | cut -f1 -d ' ')
  if [[ "$current_digest" == "$protonet_digest" ]]; then
    return 0
  else
    return 1
  fi
}

function enable_protonet_updates() {
  if [[ -z "${PLATFORM_SYS_GROUP}" ]]; then
    if [ -e ${UPDATE_ENGINE_CONFIG} ]; then
      PLATFORM_SYS_GROUP=$(cat ${UPDATE_ENGINE_CONFIG} | grep '^GROUP=' | cut -f2 -d '=')
      echo "Using OS group '${PLATFORM_SYS_GROUP}' from ${UPDATE_ENGINE_CONFIG}."
    else
      PLATFORM_SYS_GROUP="protonet"
      echo "No OS group given. Using '${PLATFORM_SYS_GROUP}' (default group)."
    fi
  else
    echo "Using OS group '${PLATFORM_SYS_GROUP}' from the command line."
  fi

	# in case there was an automatic update already running
	update_engine_client -reset_status

	# just in case someone left a key mount
  umount /usr/share/update_engine/update-payload-key.pub.pem &>/dev/null || true

	if ! is_update_key_protonet; then
    echo "$PROTONET_PUBKEY" > /tmp/protonet-image.pub.pem
    mount --bind /tmp/protonet-image.pub.pem /usr/share/update_engine/update-payload-key.pub.pem
  fi

	# reset backoff timestamp
  rm -f /var/lib/update_engine/prefs/backoff-expiry-time

	# configure update source
  echo | tee /etc/coreos/update.conf &>/dev/null <<- EOM
GROUP=$PLATFORM_SYS_GROUP
SERVER=https://coreos-update.protorz.net/update
REBOOT_STRATEGY=off
EOM

	# apply changes to update-engine
	systemctl restart update-engine.service
}

function update_os_image() {
  # run update and save its exit code
  echo "Forcing system image update"
  update_engine_client -update &>/dev/null | true
  update_status=${PIPESTATUS[0]}
  echo "Done."

  # in case we mounted a downloaded key
  umount /usr/share/update_engine/update-payload-key.pub.pem &>/dev/null
  rm -f /tmp/protonet-image.pub.pem

  if [[ "$update_status" -eq 0 ]]; then
    echo "System image update successfull."
    return 0
  else
    echo "System image update failed."
    return 1
  fi
}

function print_usage() {
  echo "usage: $0 [-r|--reboot] [-l|--reload] [-d|--debug] [-h|--help] [-c|--channel channel]"
  echo "Flags:"
  echo -e "\t-o|--osupdate\tUpdate CoreOS image"
  echo -e "\t-r|--reboot\tReboot after update finished."
  echo -e "\t-l|--reload\tTry to soft reload all services."
  echo -e "\t-c|--channel\tUse specified channel (default 'stable')."
  echo -e "\t-g|--group\tUse specified CoreOS image group (default 'protonet')."
  echo -e "\t-d|--debug\tEnable debug output."
  echo -e "\t-h|--help\tShow this help text."
}

function download_and_verify_image() {
  local image=$1
  $DOCKER tag -f $image "$image-previous" 2>/dev/null || true # do not fail, this is just for backup reason
  $DOCKER pull $image
  for layer in $(docker history --no-trunc $image | tail -n +2 | awk '{ print $1 }'); do
    # This is the most stupid way to check if all layer were downloaded correctly.
    # But it is the fastest one. The docker save command takes about 30 Minutes for all images,
    # even with output piped to /dev/null.
    if [[ ! -e /var/lib/docker/overlay/$layer || ! -e /var/lib/docker/graph/$layer ]]; then
      $DOCKER tag -f "$image-previous" $image 2>/dev/null
      exit 1
    fi
  done

  # TODO: Might wanna add --type=image for good measure once Docker 1.8 hits the CoreOS stable.
  local image_id=$(docker inspect --format '{{.Id}}' $image)
  image=${image#$REGISTRY/} # remove Registry prefix

  mkdir -p $(dirname $IMAGE_STATE_DIR/$image)
  # TODO: handle images w/ slashes like ibuildthecloud/systemd-docker:latest
  echo $image_id > $IMAGE_STATE_DIR/$image
}

function install_platform() {

  if [ "$PLATFORM_INSTALL_DEBUG" = true ]; then
    set -x
  fi

  mkdir -p $IMAGE_STATE_DIR

  if [[ -z "${CHANNEL}" ]]; then
    if [ -e ${CHANNEL_FILE} ]; then
      CHANNEL=$(cat ${CHANNEL_FILE})
      echo "Using channel '${CHANNEL}' from ${CHANNEL_FILE}."
    else
      CHANNEL="alpha"
      echo "No channel given. Using '${CHANNEL}' (default channel)."
    fi
  else
    echo "Using '${CHANNEL}' from the command line."
  fi

  download_and_verify_image $REGISTRY/configure:${CHANNEL}

  # clean up running update task!
  $DOCKER kill $CONTAINER_NAME 2>/dev/null || true
  $DOCKER rm $CONTAINER_NAME 2>/dev/null || true

  $DOCKER run --rm --name=$CONTAINER_NAME \
              --volume=/etc/:/data/ \
              --volume=/opt/bin/:/host-bin/ \
              $REGISTRY/configure:$CHANNEL

  # Make sure we're actually waiting for the network if it's required.
  systemctl enable systemd-networkd-wait-online.service

  find /etc/systemd/system -maxdepth 1 ! -name "*.sh" -type f -exec systemctl enable {} +
  # .path files need to be started!
  find /etc/systemd/system -maxdepth 1 -name "*.path" -type f | xargs basename -a | xargs systemctl restart
  # timers need to be enabled
  find /etc/systemd/system -maxdepth 1 -name "*.timer" -type f | xargs basename -a | xargs systemctl enable

  if [[ ! -f ${CHANNEL_FILE} ]] || [[ ! $(cat ${CHANNEL_FILE}) = "${CHANNEL}" ]]; then
    systemctl stop trigger-update-protonet.path
    mkdir -p $(dirname ${CHANNEL_FILE})
    echo ${CHANNEL} > ${CHANNEL_FILE}
    systemctl start trigger-update-protonet.path
  fi
  #
  # Pre-Fetch all Images
  #

  # When using a feature branch most images come from the development channel:
  available_channels="development alpha beta stable"
  if [[ ! ${available_channels} =~ ${CHANNEL} ]]; then
    echo "We're on feature channel '${CHANNEL}'"
    CHANNEL=development
  fi

  # prefetch buildstep. so the first deployment doesn't have to fetch it.
  download_and_verify_image experimentalplatform/buildstep:herokuish
  # Complex regexp to find all images names in all service files
  IMAGES=$(awk '!/^\s*[a-zA-Z0-9]+=|\[|^#|^\s*$|^\s*\-|^\s*bundle/ { sub("[^a-zA-Z0-9/:@.-]", "", $1); print $1}'  /etc/systemd/system/*.service)
  for IMAGE in $IMAGES; do
    # Doesn't work on buildstep as it is build w/ tag "latest" only.
    if [[ ! ${IMAGE} =~ "experimentalplatform/buildstep" ]]; then
      download_and_verify_image $IMAGE
    fi
  done

  if [ "$PLATFORM_INSTALL_RELOAD" = true ]; then
    echo "Reloading systemctl after update."
    systemctl restart init-protonet.service
    exit 0
  fi

  if [ "$PLATFORM_INSTALL_OSUPDATE" = true ]; then
    echo "Updating CoreOS system image."
    update_os_image || true
  fi

  if [ "$PLATFORM_INSTALL_REBOOT" = true ]; then
    echo "Rebooting after update."
    shutdown --reboot 1 "Rebooting system for experimental-platform update."
    exit 0
  fi
}

while [[ $# > 0 ]]; do
  key="$1"
  case $key in
    -r|--reboot)
      PLATFORM_INSTALL_REBOOT=true
      ;;
    -l|--reload)
      PLATFORM_INSTALL_RELOAD=true
      ;;
    -d|--debug)
      PLATFORM_INSTALL_DEBUG=true
      ;;
    -o|--osupdate)
      PLATFORM_INSTALL_OSUPDATE=true
      ;;
    -c|--channel)
      CHANNEL="$2"
      shift
      ;;
    -g|--group)
      PLATFORM_SYS_GROUP="$2"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      # unknown option
    ;;
  esac
  shift # past argument or value
done

if [ "$(id -u)" != "0" ]; then
	echo "Can not run without root permissions."
	exit 2
fi

enable_protonet_updates
install_platform
