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


function set_variables() {
    DOCKER=$(which docker)
    REGISTRY="experimentalplatform"
    CONTAINER_NAME="configure"
    CHANNEL_FILE=/etc/protonet/system/channel
    UPDATE_ENGINE_CONFIG=/etc/coreos/update.conf
    IMAGE_STATE_DIR=/etc/protonet/system/images
    HOSTNAME_FILE=/etc/protonet/hostname

    BLA=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | tr -dc 'a-z' | fold -w 6 | head -n 1)
    PLATFORM_INITIAL_HOSTNAME=${PLATFORM_INITIAL_HOSTNAME:=${BLA}}
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
}


function set_status() {
    mkdir -p /etc/protonet/system
    echo "$@" > /etc/protonet/system/configure-script-status
}

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

function prepare_os_update() {
	# in case there was an automatic update already running
	update_engine_client -reset_status

	# just in case someone left a key mount
    umount /usr/share/update_engine/update-payload-key.pub.pem &>/dev/null || true
	if ! is_update_key_protonet; then
        echo "$PROTONET_PUBKEY" > /tmp/protonet-image.pub.pem
        mount --bind /tmp/protonet-image.pub.pem /usr/share/update_engine/update-payload-key.pub.pem
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
  # TODO: DUPLICATED CODE MARK
  local image=$1
  $DOCKER tag -f $image "$image-previous" 2>/dev/null || true # do not fail, this is just for backup reason
  $DOCKER pull $image

  local driver=$($DOCKER info | grep '^Storage Driver: ' | sed -r 's/^Storage Driver: (.*)/\1/')

  # if using OverlayFS then verify layers
  if [ "$driver" == "overlay" ]; then
    for layer in $(docker history --no-trunc $image | tail -n +2 | awk '{ print $1 }'); do
      # This is the most stupid way to check if all layer were downloaded correctly.
      # But it is the fastest one. The docker save command takes about 30 Minutes for all images,
      # even with output piped to /dev/null.
      if [[ ! -e /var/lib/docker/overlay/$layer || ! -e /var/lib/docker/graph/$layer ]]; then
        $DOCKER tag -f "$image-previous" $image 2>/dev/null
        exit 1
      fi
    done
  fi

  # TODO: Might wanna add --type=image for good measure once Docker 1.8 hits the CoreOS stable.
  local image_id=$(docker inspect --format '{{.Id}}' $image)
  image=${image#$REGISTRY/} # remove Registry prefix

  mkdir -p $(dirname $IMAGE_STATE_DIR/$image)
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

  prepare_os_update

  download_and_verify_image $REGISTRY/configure:${CHANNEL}

  # clean up running update task!
  $DOCKER kill $CONTAINER_NAME 2>/dev/null || true
  $DOCKER rm $CONTAINER_NAME 2>/dev/null || true

  mkdir -p /etc/protonet
  [[ -d $HOSTNAME_FILE ]] && rm -rf /etc/protonet/hostname
  if [[ ! -f $HOSTNAME_FILE ]]; then
    echo "Setting hostname to '$PLATFORM_INITIAL_HOSTNAME'."
    echo $PLATFORM_INITIAL_HOSTNAME > $HOSTNAME_FILE
  fi

  set_status "configuring"
  # TODO: /etc/docker and /root/.docker could be mounted from skvs
  $DOCKER run --rm --name=${CONTAINER_NAME} \
              --cap-add=SYS_ADMIN \
              --volume=/opt/:/mnt/opt/ \
              --volume=/etc/:/mnt/etc/ \
              --volume=/usr/:/mnt/usr/ \
              --volume=/var/:/mnt/var/ \
              --volume=$(which docker):$(which docker):ro \
              --volume $(which systemctl):$(which systemctl):ro \
              --volume $(which update_engine_client):$(which update_engine_client):ro \
              --volume /dev:/dev:rw \
              --volume /etc/docker:/etc/docker:ro \
              --volume /root/.docker:/root/.docker:ro \
              --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
              --volume /var/run/dbus:/var/run/dbus:rw \
              --volume=/var/run/docker.sock:/var/run/docker.sock:rw \
              --volume /var/run/systemd:/var/run/systemd:ro \
              --volume=/lib64:/lib64:ro \
              -e "CHANNEL_FILE=/mnt${CHANNEL_FILE}" \
              -e "CHANNEL=${CHANNEL}" \
              -e "IMAGE_STATE_DIR=${IMAGE_STATE_DIR}" \
              -e "REGISTRY=${REGISTRY}" \
              -e "PLATFORM_INSTALL_RELOAD=${PLATFORM_INSTALL_RELOAD}" \
              -e "PLATFORM_INSTALL_OSUPDATE=${PLATFORM_INSTALL_OSUPDATE}" \
              -e "PLATFORM_SYS_GROUP=${PLATFORM_SYS_GROUP}" \
              -e "UPDATE_ENGINE_CONFIG=/mnt${UPDATE_ENGINE_CONFIG}" \
              ${REGISTRY}/configure:${CHANNEL}
  # TODO trap - SIGINT SIGTERM EXIT
  set_status "done"

    # in case we mounted a downloaded key
    umount /usr/share/update_engine/update-payload-key.pub.pem &>/dev/null || true
    rm -f /tmp/protonet-image.pub.pem || true


  if [ "$PLATFORM_INSTALL_REBOOT" = true ]; then
    echo "Rebooting after update."
    shutdown --reboot 1 "Rebooting system for experimental-platform update."
    exit 0
  fi
}


function parse_options() {
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
}


function check_for_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "Can not run without root permissions."
        exit 2
    fi
}


parse_options "$@"
check_for_root
trap "set_status 'cancelled'" SIGINT SIGTERM EXIT
set_variables
set_status "preparing"
install_platform
