#!/bin/bash
set -e

DOCKER=$(which docker)
REGISTRY="experimentalplatform"
CONTAINER_NAME="configure"
CHANNEL_FILE=/etc/protonet/system/channel
IMAGE_STATE_DIR=/etc/protonet/system/images

REBOOT=false
RELOAD=false
DEBUG=false

function print_usage() {
  echo "usage: $0 [-r|--reboot] [-l|--reload] [-d|--debug] [-h|--help] [-c|--channel channel]"
  echo "Flags:"
  echo -e "\t-r|--reboot\tReboot after update finished."
  echo -e "\t-l|--reload\tTry to soft reload all services."
  echo -e "\t-c|--channel\tUse specified channel (default 'stable')."
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

  local image_id=$(docker images | awk "(\$1 \":\" \$2) == \"$image\" {print \$3}")
  image=${image#$REGISTRY/} # remove Registry prefix

  mkdir -p $(dirname $IMAGE_STATE_DIR/$image)
  echo $image_id > $IMAGE_STATE_DIR/$image
}

touch /var/run/protonet_updating


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
    -c|--channel)
      CHANNEL="$2"
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

mkdir -p $IMAGE_STATE_DIR

if [ -z "$CHANNEL" ]; then
  if [ -e $CHANNEL_FILE ]; then
    CHANNEL=$(cat $CHANNEL_FILE)
    echo "Using channel '$CHANNEL' from $CHANNEL_FILE."
  else
    CHANNEL=stable
    echo "No channel given. Using '$CHANNEL' (default channel)."
  fi
fi

download_and_verify_image $REGISTRY/configure:$CHANNEL

# required in init-protonet.service:
download_and_verify_image ibuildthecloud/systemd-docker

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

# Pre-Fetch all Images
# Complex regexp to find all images names in all service files
IMAGES=$(grep -hor -i "$REGISTRY\/[a-zA-Z0-9:_-]\+\s\?" /etc/systemd/system/*.service)
for IMAGE in $IMAGES; do
  download_and_verify_image $IMAGE
done

mkdir -p $(dirname $CHANNEL_FILE)
echo $CHANNEL > $CHANNEL_FILE

if [ "$RELOAD" = true ]; then
  echo "Reloading systemctl after update."
  systemctl restart init-protonet.service
  rm -f /var/run/protonet_updating
  exit 0
fi

if [ "$REBOOT" = true ]; then
  echo "Rebooting after update."
  shutdown --reboot "Rebooting system for experimental-platform update."
  exit 0
fi
rm -f /var/run/protonet_updating