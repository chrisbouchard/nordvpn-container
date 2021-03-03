#!/usr/bin/env bash

set -o errtrace

IMAGE_NAME='chrisbouchard/nordvpn'
GITHUB_REPO='chrisbouchard/nordvpn'

# URL to NordVPN RPM, retrieved from https://nordvpn.com/download
# TODO: Is there a way we can get the latest URL programmatically?
NORDVPN_REPO_RPM='https://repo.nordvpn.com/yum/nordvpn/centos/noarch/Packages/n/nordvpn-release-1.0.0-1.noarch.rpm'

IMAGE_VERSION=${IMAGE_VERSION:-latest}
IMAGE_REGISTRY=${IMAGE_REGISTRY:-docker.io}

MAINTAINER='Chris Bouchard <chris@upliftinglemma.net>'
VCS_URL="https://github.com/$GITHUB_REPO"
VCS_REF=${VCS_REF:-$(git rev-parse HEAD)}
CREATED_BY=${CREATED_BY:-$(basename "$0")}

BUILD_DIR="$PWD/build"
DNF_CACHE_DIR="$BUILD_DIR/dnfcache"

BUILDAH_DNF_OPTS=(--volume "$DNF_CACHE_DIR:/var/cache/dnf:z")
IMAGE_ID="$IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_VERSION"

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

step 'Creating build cache directory'
mkdir -p "$DNF_CACHE_DIR"

step 'Creating container'
container=$(buildah from registry.fedoraproject.org/fedora)
trap "cleanup_container '$container'" EXIT
buildah config \
    --label maintainer="$MAINTAINER" \
    --label vcs-url="$VCS_URL" \
    --label vcs-ref="$VCS_REF" \
    --created-by "$CREATED_BY" \
    --entrypoint '["/usr/sbin/nordvpnd"]' \
    "$container"

step 'Installing NordVPN and Dependencies'
buildah run --tty "${BUILDAH_DNF_OPTS[@]}" -- "$container" bash -i -c \
    "dnf install --assumeyes '$NORDVPN_REPO_RPM' && \
        dnf install --assumeyes procps nordvpn"

step 'Committing container'
buildah commit "$container" "$IMAGE_ID"

