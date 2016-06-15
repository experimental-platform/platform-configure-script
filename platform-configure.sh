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
    REGISTRY="quay.io/experimentalplatform"
    CONTAINER_NAME="configure"
    PLATFORM_BASENAME=${PLATFORM_BASENAME:=""}

    CHANNEL_FILE=${PLATFORM_BASENAME}/etc/protonet/system/channel
    UPDATE_ENGINE_CONFIG=${PLATFORM_BASENAME}/etc/coreos/update.conf
    IMAGE_STATE_DIR=${PLATFORM_BASENAME}/etc/protonet/system/images
    HOSTNAME_FILE=${PLATFORM_BASENAME}/etc/protonet/hostname

    PLATFORM_INITIAL_HOSTNAME=${PLATFORM_INITIAL_HOSTNAME:="protonet"}
    PLATFORM_INSTALL_REBOOT=${PLATFORM_INSTALL_REBOOT:=false}
    PLATFORM_INSTALL_RELOAD=${PLATFORM_INSTALL_RELOAD:=false}
    PLATFORM_INSTALL_OSUPDATE=${PLATFORM_INSTALL_OSUPDATE:=false}
    PLATFORM_INSTALL_DEBUG=${PLATFORM_INSTALL_DEBUG:=false}

    # these two are passed to platform-configure image
    # in order to install a feature-branch for a single service
    SERVICE_NAME=${SERVICE_NAME:=""}
    SERVICE_TAG=${SERVICE_TAG:=""}
}


function set_status() {
    mkdir -p ${PLATFORM_BASENAME}/etc/protonet/system
    echo "$@" > ${PLATFORM_BASENAME}/etc/protonet/system/configure-script-status
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
    for layer in $(${DOCKER} history --no-trunc $image | tail -n +2 | awk '{ print $1 }'); do
      # This is the most stupid way to check if all layer were downloaded correctly.
      # But it is the fastest one. The docker save command takes about 30 Minutes for all images,
      # even with output piped to /dev/null.
      if [[ ! -e ${PLATFORM_BASENAME}/var/lib/docker/overlay/$layer || ! -e ${PLATFORM_BASENAME}/var/lib/docker/graph/$layer ]]; then
        $DOCKER tag -f "$image-previous" $image 2>/dev/null
        exit 1
      fi
    done
  fi

  # TODO: Might wanna add --type=image for good measure once Docker 1.8 hits the CoreOS stable.
  local image_id=$(${DOCKER} inspect --format '{{.Id}}' $image)
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
      CHANNEL="soul3"
      echo "No channel given. Using '${CHANNEL}' (default channel)."
    fi
  else
    echo "Using '${CHANNEL}' from the command line."
  fi

  download_and_verify_image $REGISTRY/configure:${CHANNEL}

  # clean up running update task!
  $DOCKER kill $CONTAINER_NAME 2>/dev/null || true
  $DOCKER rm $CONTAINER_NAME 2>/dev/null || true

  mkdir -p ${PLATFORM_BASENAME}/etc/protonet
  [[ -d ${HOSTNAME_FILE} ]] && rm -rf ${HOSTNAME_FILE}
  if [[ ! -f ${HOSTNAME_FILE} ]]; then
    echo "Setting hostname to '$PLATFORM_INITIAL_HOSTNAME'."
    echo $PLATFORM_INITIAL_HOSTNAME > $HOSTNAME_FILE
  fi

    if [[ "${PLATFORM_INSTALL_OSUPDATE}" = true ]]; then
        echo "CoreOS System Update: START"
        set_status "osupdate"
        if [[ -x ${PLATFORM_BASENAME}/opt/bin/update_os ]]; then
            ${PLATFORM_BASENAME}/opt/bin/update_os && echo "CoreOS System Update: DONE" || echo "CoreOS System Update: ERROR"
        else
            echo "CoreOS System Update: Script not found. Please try again  "
        fi
    fi

  set_status "configuring"
  # TODO: /etc/docker and /root/.docker could be mounted from skvs
  rkt run --insecure-options=image \
  --volume opt,kind=host,source=/opt/,readOnly=false \
  --volume etc,kind=host,source=/etc/,readOnly=false \
  --volume usr,kind=host,source=/usr/,readOnly=true  \
  --volume var,kind=host,source=/var/,readOnly=false \
  --volume dev,kind=host,source=/dev/,readOnly=false \
  --volume etc-docker,kind=host,source=/etc/docker,readOnly=true \
  --volume dot-docker,kind=host,source=/root/.docker,readOnly=true \
  --volume cgroup,kind=host,source=/sys/fs/cgroup,readOnly=true \
  --volume dbus,kind=host,source=/var/run/dbus,readOnly=false \
  --volume docker-sock,kind=host,source=/var/run/docker.sock,readOnly=false \
  --volume systemd,kind=host,source=/var/run/systemd,readOnly=true \
  --volume dbus,kind=host,source=/var/run/dbus,readOnly=false \
  --volume docker-bin,kind=host,source=$(which docker),readOnly=true \
  --volume systemctl-bin,kind=host,source=$(which systemctl),readOnly=true \
  --mount volume=opt,target=/mnt/opt/ \
  --mount volume=etc,target=/mnt/etc/ \
  --mount volume=usr,target=/mnt/usr/ \
  --mount volume=var,target=/mnt/var/ \
  --mount volume=dev,target=/mnt/dev/ \
  --mount volume=etc-docker,target=/etc/docker \
  --mount volume=dot-docker,target=/root/.docker \
  --mount volume=cgroup,target=/sys/fs/cgroup \
  --mount volume=dbus,target=/var/run/dbus \
  --mount volume=docker-sock,target=/var/run/docker.sock \
  --mount volume=systemd,target=/var/run/systemd \
  --mount volume=docker-bin,target=$(which docker) \
  --mount volume=systemctl-bin,target=$(which systemctl) \
  --set-env="CHANNEL_FILE=/mnt${CHANNEL_FILE}" \
  --set-env="CHANNEL=${CHANNEL}" \
  --set-env="IMAGE_STATE_DIR=${IMAGE_STATE_DIR}" \
  --set-env="REGISTRY=${REGISTRY}" \
  --set-env="PLATFORM_INSTALL_RELOAD=${PLATFORM_INSTALL_RELOAD}" \
  --set-env="PLATFORM_INSTALL_OSUPDATE=${PLATFORM_INSTALL_OSUPDATE}" \
  --set-env="PLATFORM_SYS_GROUP=${PLATFORM_SYS_GROUP}" \
  --set-env="UPDATE_ENGINE_CONFIG=/mnt${UPDATE_ENGINE_CONFIG}" \
  --set-env="SERVICE_NAME=${SERVICE_NAME}" \
  --set-env="SERVICE_TAG=${SERVICE_TAG}" \
  protonet.com/platform/cfg:${CHANNEL}
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
                export PLATFORM_SYS_GROUP
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
set_status "done"
trap - SIGINT SIGTERM EXIT

if [ "$PLATFORM_INSTALL_REBOOT" = true ]; then
  echo "Rebooting after update."
  shutdown --reboot 1 "Rebooting system for experimental-platform update."
fi
