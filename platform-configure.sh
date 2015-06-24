#!/bin/bash
set -e
DOCKER=$(which docker)
REGISTRY="experimentalplatform"
CONTAINER_NAME="configure"

REBOOT=false
RELOAD=false
DEBUG=false

function print_usage() {
  echo "usage: $0 [-r|--reboot] [-l|--reload] [-d|--debug] [-h|--help] [-t|--tag tag]"
  echo "Flags:"
  echo -e "\t-r|--reboot\tReboot after update finished."
  echo -e "\t-l|--reload\tTry to soft reload all services."
  echo -e "\t-t|--tag\tUpdate to specified tag (default updates to newest version)."
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
      echo "Layer '$layer' of '$image' missing. Switching to previous version (if there was one)."
      $DOCKER tag -f "$image-previous" $image 2>/dev/null
      exit 1
    fi
  done
}

while [[ $# > 0 ]]; do
  key="$1"
  case $key in
    -r|--reboot)
      REBOOT=true
      ;;
    -l|--reload)
      RELOAD=true
      ;;
    -d|--debug)
      DEBUG=true
      ;;
    -t|--tag)
      TAG="$2"
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

if [ "$DEBUG" = true ]; then
  set -x
fi

if [ "$(id -u)" != "0" ]; then
  echo "Can not run without root pemissions."
  exit 2
fi

if [ -z "$TAG" ]; then
  echo "Update to newest Tag is not implemented yet! Please specify tag via --tag option and run again!"
  exit 1
fi

download_and_verify_image $REGISTRY/configure:$TAG

# clean up running update task!
$DOCKER kill $CONTAINER_NAME 2>/dev/null || true
$DOCKER rm $CONTAINER_NAME 2>/dev/null || true

$DOCKER run --rm --name=$CONTAINER_NAME \
            --volume=/etc/:/data/ \
            --volume=/opt/bin/:/host-bin/ \
            $REGISTRY/configure:$TAG

find /etc/systemd/system -maxdepth 1 ! -name "*.sh" -type f -exec systemctl enable {} +

# Pre-Fetch all Images
# Complex regexp to find all images names in all service files
IMAGES=$(grep -hor -i "$REGISTRY\/[a-zA-Z0-9:_-]\+\s\?" /etc/systemd/system/*.service)
for IMAGE in $IMAGES; do
  download_and_verify_image $IMAGE
done

if [ "$RELOAD" = true ]; then
  echo "Reloading systemctl after update."
  systemctl restart init-protonet.service
  exit 0
fi

if [ "$REBOOT" = true ]; then
  echo "Rebooting after update."
  shutdown --reboot 5 "Rebooting system for experimental-platform update."
  exit 0
fi
