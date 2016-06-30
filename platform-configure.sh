#!/bin/bash

set -euo pipefail
IFS=$'\n\t'


# Copyright 2015-2016 Protonet GmbH
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
    CHANNEL=${CHANNEL:=""}
    PLATFORM_SYS_GROUP=""
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
    local image
    image=$1
    echo -ne "\t Image ${image}..."
    RETRIES=0
    MAXRETRIES=10
    while ( ! $DOCKER pull $image &>/dev/null ) && [ $RETRIES -ne $MAXRETRIES ]; do
        sleep 1
        echo -n " Pull failed, retrying.... "
        RETRIES=$(($RETRIES+1))
    done

    if [ $RETRIES -eq $MAXRETRIES ]; then
      echo " Failed to retrieve $image"
      exit 1
    fi

    local driver=$(${DOCKER} info | grep '^Storage Driver: ' | sed -r 's/^Storage Driver: (.*)/\1/')
    # if using OverlayFS then verify layers
    if [ "${driver}" == "overlay" ]; then
        # TODO: this basically works with ZFS too, it just has slightly different path names
        for layer in $(${DOCKER} history --no-trunc ${image} | tail -n +2 | awk '{ print $1 }'); do
            # This is the most stupid way to check if all layer were downloaded correctly.
            # But it is the fastest one. The docker save command takes about 30 Minutes for all images,
            # even with output piped to /dev/null.
            if [[ ! -e ${PLATFORM_BASENAME}/var/lib/docker/overlay/${layer} || ! -e ${PLATFORM_BASENAME}/var/lib/docker/graph/${layer} ]]; then
                echo "Image '${image}' arrived broken"
                exit 1
            fi
        done
    fi

    # TODO: Might wanna add --type=image for good measure once Docker 1.8 hits the CoreOS stable.
    local image_id=$(${DOCKER} inspect --format '{{.Id}}' ${image})
    image=${image#$REGISTRY/} # remove Registry prefix

    mkdir -p $(dirname ${IMAGE_STATE_DIR}/${image})
    echo $image_id > ${IMAGE_STATE_DIR}/${image}
    echo "DONE."
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
  $DOCKER run --rm --name=${CONTAINER_NAME} \
              --privileged=true \
              --volume=/opt/:/mnt/opt/ \
              --volume=/etc/:/mnt/etc/ \
              --volume=/usr/:/mnt/usr/ \
              --volume=/var/:/mnt/var/ \
              --volume=$(which docker):$(which docker):ro \
              --volume=$(which systemctl):$(which systemctl):ro \
              --volume=/dev:/dev:rw \
              --volume=/etc/docker:/etc/docker:ro \
              --volume=/root/.docker:/root/.docker:ro \
              --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro \
              --volume=/var/run/dbus:/var/run/dbus:rw \
              --volume=/var/run/docker.sock:/var/run/docker.sock:rw \
              --volume=/var/run/systemd:/var/run/systemd:ro \
              -e "CHANNEL_FILE=/mnt${CHANNEL_FILE}" \
              -e "CHANNEL=${CHANNEL}" \
              -e "IMAGE_STATE_DIR=${IMAGE_STATE_DIR}" \
              -e "REGISTRY=${REGISTRY}" \
              -e "PLATFORM_INSTALL_RELOAD=${PLATFORM_INSTALL_RELOAD}" \
              -e "PLATFORM_INSTALL_OSUPDATE=${PLATFORM_INSTALL_OSUPDATE}" \
              -e "PLATFORM_SYS_GROUP=${PLATFORM_SYS_GROUP}" \
              -e "UPDATE_ENGINE_CONFIG=/mnt${UPDATE_ENGINE_CONFIG}" \
              -e "SERVICE_NAME=${SERVICE_NAME}" \
              -e "SERVICE_TAG=${SERVICE_TAG}" \
              ${REGISTRY}/configure:${CHANNEL}
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
/opt/bin/button "rainbow" &>/dev/null || true
install_platform
set_status "done"
trap - SIGINT SIGTERM EXIT

if [ "$PLATFORM_INSTALL_REBOOT" = true ]; then
  echo "Rebooting after update."
  shutdown --reboot 1 "Rebooting system for experimental-platform update."
fi

