#!/bin/bash

#=====================================================================
# autolocation.sh
#
# Detect which OS X Network Location to use based on Wireless SSID, IP
# addresses, or other means.
#
# Written by: Gregory Ruiz-Ade <gregory@ruiz-ade.com>
#
#---------------------------------------------------------------------
# LIMITATIONS:
#
# * Location names must be single-word strings due to not wanting to
#   deal with bash quoting limitations.
#
# * Matching by IP address currently requires an exact match, I may
#   figure out a way to do subnet matching in the future, like:
#   - 10.0.1.0/24
#   - 10.0.0.0/8
#   It could be handy...
#---------------------------------------------------------------------
#
#---------------------------------------------------------------------
# Idea blatantly stolen from:
#
# Original author: Onne Gorter <o.gorter@gmail.com>
# url: http://tech.inhelsinki.nl/locationchanger/
#
# Modifications by Timothy Baldock <tb@entropy.me.uk>
#=====================================================================

#---------------------------------------------------------------------
# Locations which we should try to detect.

# Home
declare -a LOC_NAME
declare -a LOC_SSID
LOC_NAME[0]="Home"
LOC_SSID[0]="fupa"

# Work
LOC_NAME[1]="Work"
LOC_SSID[1]="WEX-Inc"
#---------------------------------------------------------------------

SELF=$(echo $0 | sed 's#^.*/##')

# log file
LOGFILE="${HOME}/.autolocation.log"

# Stuff all output into the log file (anything we don't shove through
# logger)
exec 1>>${LOGFILE} 2>&1

# Syslog facility/level to use for various conditions
ERRLOG="user.error"
WARNLOG="user.warn"
INFOLOG="user.info"

#---------------------------------------------------------------------
# Binaries that we need...

# logger(1)
LOGGER="/usr/bin/logger"

# scselect(8)
SCSELECT="/usr/sbin/scselect"

# notifier
NOTIFY="/usr/bin/osascript"

if [ ! -x ${SCSELECT} ] || [ ! -x ${LOGGER} ] || [ ! -x ${NOTIFY} ]; then
    echo ""
    echo "$SELF - FATAL"
    echo "The following binaries are required and were not found:"
    echo ""
    echo "  $SCSELECT"
    echo "  $LOGGER"
    echo "  $NOTIFY"
    echo ""
    echo "ABORTING."
    echo ""
    exit 1
fi

# Set some options we'll use throughout

# logger(1)
LOGGER_OPTS="-i -s -t ${SELF}"
LOGGER="${LOGGER} ${LOGGER_OPTS}"

#=====================================================================
# Functions
#=====================================================================

#---------------------------------------------------------------------
# get_ssid
#
# Usage:
#
# ssid=
# get_ssid ssid
# echo $ssid

function get_ssid ()
{
    airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport -I"

    ssid=$(${airport} 2>> >(${LOGGER} -p ${ERRLOG}) \
	| grep ' SSID:' \
	| cut -d ':' -f 2 \
	| tr -d ' ')

    eval "$1=${ssid}"
}

#---------------------------------------------------------------------
# get_location
#
# Usage:
#
# location=
# get_location location
# echo $location

function get_location ()
{
    # Grab the location, send any errors from scselect to logger
    location=$(${SCSELECT} 2>> >(${LOGGER} -p ${ERRLOG}) \
	| grep '^ \* ' \
	| sed 's/.*(\(.*\))/\1/')

    eval "$1=${location}"
}

#---------------------------------------------------------------------
# set_location
#
# Usage
#
# set_location <location_name>

function set_location ()
{
    # What's the requested location?
    location=$1

    # Log the activity
    ${LOGGER} -p ${INFOLOG} "Setting Network Location to: $location"

    # Set the location and send scselect output to logger
    ${SCSELECT} ${location} 1>> >(${LOGGER} -p ${INFOLOG}) 2>> >(${LOGGER} -p ${ERRLOG})

    # If scselect failed, alert and bail.
    if [ ${?} -ne 0 ]; then

        ${LOGGER} -p ${ERRLOG} "Error selecting Location $location!"

        ${NOTIFY} -e 'display notification "ERROR: Unable to set Location: '"${location}"'"'

        exit 1

    fi

    # Swap ssh configs
    if [ -f ~/.ssh/config.${location} ] ; then
        ${LOGGER} -p ${INFOLOG} "Swapping SSH config to $location..."
        rm ~/.ssh/config
        ln -s ~/.ssh/config.${location} ~/.ssh/config
    fi

    # Remove all zsh configs
    i=0;
    while [ ${i} -lt ${#LOC_NAME[@]} ]; do
        locName="${LOC_NAME[$i]}";
        sed -i.bak0 '/#'"$locName"/',/#\/'"$locName"'/d' ~/.zshrc
        i=$(expr ${i} + 1)
    done

    # Add correct zsh config
    if [ -f ~/.${location}rc ] ; then
        ${LOGGER} -p ${INFOLOG} "Adding zsh config section for $location..."
        sed -i.bak1 '/#Begin'"$location"'Section/r .'"$location"'rc' ~/.zshrc
    fi
}

#=====================================================================
# Main
#=====================================================================

# Grab our current location
CUR_LOC=
get_location CUR_LOC
${LOGGER} -p ${INFOLOG} "Current location is: $CUR_LOC"

# If the location is changing, figure out what we need to change it to
# and set the new location.
changed_loc=0

${LOGGER} -p ${INFOLOG} "Setting Network Location $CUR_LOC"
set_location ${CUR_LOC}
changed_loc=1

# Check the current location again to see if it's changed
CUR_LOC=
get_location CUR_LOC
${LOGGER} -p ${INFOLOG} "Current location is now: $CUR_LOC"

# If we think we've changed network locations...
if [ ${changed_loc} -eq 1 ]; then

    # See if we really did change...
    if [ "$CUR_LOC" == "$CUR_LOC" ]; then

        # Yay, announce our success with pride!
        ${NOTIFY} -e 'display notification "Updated Location: '"$CUR_LOC"'"'

        ${LOGGER} -p ${INFOLOG} "Updated Location: $CUR_LOC;"

    else

        # Boo, we completely failed, and need to tell someone.
        ${NOTIFY} -e 'display notification "FAILED! Unable to update Location to '"$CUR_LOC"'!"'

        ${LOGGER} -p ${ERRLOG} "FAILED! Unable to update Location to $CUR_LOC!"
    fi

fi
