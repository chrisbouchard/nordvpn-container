#!/usr/bin/env bash

set -o errtrace

IMAGE_NAME='chrisbouchard/nordvpn'
GITHUB_REPO='chrisbouchard/nordvpn'

# TODO: Is there a way we can get the latest URL programmatically?
NORDVPN_REPO_DEB_URL='https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb'

IMAGE_VERSION=${IMAGE_VERSION:-latest}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-docker.io}

MAINTAINER='Chris Bouchard <chris@upliftinglemma.net>'
VCS_URL="https://github.com/$GITHUB_REPO"
VCS_REF=${VCS_REF:-$(git rev-parse HEAD)}
CREATED_BY=${CREATED_BY:-$(basename "$0")}

IMAGE_ID="$IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_VERSION"

BUILD_DIR="$PWD/build"
NORD_REPO_DEB_FILE="$BUILD_DIR/nordvpn-release.deb"

BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
WHITE=$(tput setaf 7)
RESET=$(tput sgr0)

step() {
    echo
    echo "$BOLD$GREEN>>> $WHITE$1...$RESET"
}

complain_and_die() {
    echo
    echo "$BOLD$RED!!!$RESET Command failed with exit code $1"
    trap - ERR
    exit 1
}

cleanup_container() {
    local container="$1"
    step 'Deleting working container'
    buildah rm "$container"
}

trap 'complain_and_die $?' ERR

step 'Creating build directory'
mkdir -p "$BUILD_DIR"

step 'Creating container'
container=$(buildah from docker.io/ubuntu:18.04)
trap "cleanup_container '$container'" EXIT
buildah config \
    --author "$MAINTAINER" \
    --cmd '' \
    --created-by "$CREATED_BY" \
    --entrypoint '["/entrypoint.sh"]' \
    --label maintainer="$MAINTAINER" \
    --label vcs-url="$VCS_URL" \
    --label vcs-ref="$VCS_REF" \
    --volume /run/nordvpn \
    --volume /run/secrets/nordvpn \
    "$container"

step 'Add Startup Script'
buildah copy "$container" entrypoint.sh /entrypoint.sh

step 'Downloading NordVPN Repository DEB'
wget -O "$NORD_REPO_DEB_FILE" "$NORDVPN_REPO_DEB_URL"

step 'Installing NordVPN and Dependencies'
buildah run \
    --volume "$NORD_REPO_DEB_FILE:/tmp/nordvpn-release.deb:z" \
    -- \
    "$container" bash <<EOF
        ( set -x &&
            apt-get update &&
            apt-get install -y /tmp/nordvpn-release.deb ca-certificates &&
            apt-get update &&
            apt-get install -y nordvpn systemd
        ) &&
        rm -rf /var/lib/apt/lists/*
EOF

step 'Committing container'
buildah commit "$container" "$IMAGE_ID"

