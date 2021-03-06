#!/usr/bin/env bash

set -o errtrace
set -o monitor

NORDVPN_KILLSWITCH=${NORDVPN_KILLSWITCH:-on}
NORDVPN_PASSWORD_FILE=${NORDVPN_PASSWORD_FILE:-/run/secrets/nordvpn/password}
NORDVPN_TECHNOLOGY=${NORDVPN_TECHNOLOGY:-NordLynx}


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

trap 'complain_and_die $?' ERR


if [[ -z "$NORDVPN_USERNAME" ]]
then
    echo 'Error: Username expected in $NORDVPN_USERNAME' >&2
    exit 1
fi

if [[ ! -e "$NORDVPN_PASSWORD_FILE" ]]
then
    echo "Error: Password expected in $NORDVPN_PASSWORD_FILE (\$NORDVPN_PASSWORD_FILE)" >&2
    exit 1
fi

IFS= read NORDVPN_PASSWORD <"$NORDVPN_PASSWORD_FILE"


step 'Starting NordVPN Daemon'
# Start NordVPN in the background. Its output will still go to standard output.
nordvpnd &

# Wait for the daemon to be available
while ! nordvpn status &>/dev/null
do
    sleep 1
done

step 'Configuring NordVPN'
nordvpn set technology "$NORDVPN_TECHNOLOGY"

if [[ -n "$NORDVPN_PROTOCOL" ]]
then
    nordvpn set protocol "$NORDVPN_PROTOCOL"
fi

if [[ -n "$NORDVPN_WHITELIST_SUBNETS" ]]
then
    for subnet in $NORDVPN_WHITELIST_SUBNETS
    do
        nordvpn whitelist add subnet "$subnet"
    done
fi

step 'Logging into NordVPN'
# NordVPN won't allow login from a non-TTY, so no input redirection.
nordvpn login --username "$NORDVPN_USERNAME" --password "$NORDVPN_PASSWORD"

step 'Connecting to NordVPN'
nordvpn connect "${NORDVPN_CONNECT_ARGS[@]}"

step 'Configuring Kill Switch'
nordvpn set killswitch "$NORDVPN_KILLSWITCH"

if [[ -n "$NOTIFY_SOCKET" ]]
then
    step 'Notifying Systemd that NordVPN is Connected'
    systemd-notify --ready --status='Connected'
fi

# Put the NordVPN daemon back in control
fg %nordvpnd

