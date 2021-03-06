#!/usr/bin/env bash

set -o errtrace

IMAGE_NAME='chrisbouchard/nordvpn'
GITHUB_REPO='chrisbouchard/nordvpn'

# TODO: Is there a way we can get the latest URL programmatically?
NORDVPN_REPO_RPM_URL='https://repo.nordvpn.com/yum/nordvpn/centos/noarch/Packages/n/nordvpn-release-1.0.0-1.noarch.rpm'

IMAGE_VERSION=${IMAGE_VERSION:-latest}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-docker.io}

MAINTAINER='Chris Bouchard <chris@upliftinglemma.net>'
VCS_URL="https://github.com/$GITHUB_REPO"
VCS_REF=${VCS_REF:-$(git rev-parse HEAD)}
CREATED_BY=${CREATED_BY:-$(basename "$0")}

IMAGE_ID="$IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_VERSION"

FEDORA_VERSION=33

BUILD_DIR="$PWD/build"
NORD_REPO_RPM_FILE="$BUILD_DIR/nordvpn-release.rpm"

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
container=$(buildah from "registry.fedoraproject.org/fedora-minimal:$FEDORA_VERSION")
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

step 'Downloading NordVPN Repository RPM'
wget -O "$NORD_REPO_RPM_FILE" "$NORDVPN_REPO_RPM_URL"

step 'Installing NordVPN and Dependencies'
buildah run --tty \
    --volume "$NORD_REPO_RPM_FILE:/tmp/nordvpn-release.rpm:z" \
    -- \
    "$container" bash -i -o errexit -o xtrace -c "
        # We got this RPM directly from NordVPN's servers, so we're going to trust it. And since microdnf can't install
        # local RPMs, we'll install it directly.
        rpm --install --nosignature /tmp/nordvpn-release.rpm
        microdnf update --assumeyes
        # Install NordVPN and its implicit dependencies, which aren't installed by default in fedora-minimal.
        microdnf install --assumeyes iproute nordvpn procps-ng systemd
        microdnf clean all
    "

step 'Committing container'
buildah commit "$container" "$IMAGE_ID"

