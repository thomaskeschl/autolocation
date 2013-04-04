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
LOC_NAME[0]="Home"
LOC_SSID[0]="home_network"
LOC_EN0IP[0]="10.0.1.41"
LOC_EN1IP[0]="10.0.1.41"

# Work
#LOC_NAME[1]="Work"
#LOC_SSID[1]="work_network"
#LOC_EN0IP[1]=
#LOC_EN1IP[1]=
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

# growlnotify
GROWL="/usr/local/bin/growlnotify"

if [ ! -x $SCSELECT ] || [ ! -x $LOGGER ] || [ ! -x $GROWL ]; then
    echo ""
    echo "$SELF - FATAL"
    echo "The following binaries are required and were not found:"
    echo ""
    echo "  $SCSELECT"
    echo "  $LOGGER"
    echo "  $GROWL"
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

    ssid=$($airport 2>> >($LOGGER -p $ERRLOG) \
	| grep ' SSID:' \
	| cut -d ':' -f 2 \
	| tr -d ' ')

    eval "$1=$ssid"
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
    location=$($SCSELECT 2>> >($LOGGER -p $ERRLOG) \
	| grep '^ \* ' \
	| sed 's/.*(\(.*\))/\1/')

    eval "$1=$location"
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
    $LOGGER -p $INFOLOG "Setting Network Location to: $location"

    # Set the location and send scselect output to logger
    $SCSELECT $location 1>> >($LOGGER -p $INFOLOG) 2>> >($LOGGER -p $ERRLOG)

    # If scselect failed, alert and bail.
    if [ ${?} -ne 0 ]; then

	$LOGGER -p $ERRLOG "Error selecting Location $location!"

	$GROWL -s -p2 -n "Auto Location" \
	    -a "/Applications/Utilities/Airport Utility.app/" \
	    -m "ERROR: Unable to set Location: $location"

	exit 1

    fi
}

#=====================================================================
# Main
#=====================================================================

# Grab our current location
CUR_LOC=
get_location CUR_LOC
$LOGGER -p $INFOLOG "Current location is: $CUR_LOC"

# Get the associated SSID
SSID=
get_ssid SSID
if [ -n "$SSID" ]; then
    $LOGGER -p $INFOLOG "Associated to SSID $SSID"
else
    $LOGGER -p $INFOLOG "Not associated to any SSID"
fi

# Get the ethernet IP address
EN0IP=$(ifconfig en0 | grep -w inet | cut -d ' ' -f 2)
$LOGGER -p $INFOLOG "en0 IP: $EN0IP"

# Get the WiFi IP address
EN1IP=$(ifconfig en1 | grep -w inet | cut -d ' ' -f 2)
$LOGGER -p $INFOLOG "en1 IP: $EN1IP"

# Figure out which location we need to select based on the current
# network status.
NEW_LOC=
REASON=
i=0;
while [ $i -lt ${#LOC_NAME[@]} ]; do
    if [ "$SSID" == "${LOC_SSID[$i]}" ]; then
	NEW_LOC="${LOC_NAME[$i]}"
	REASON="Matched WiFi"
	break
    elif [ -n "$EN0IP" && "$EN0IP" == "${LOC_EN0IP[$i]}" ]; then
	NEW_LOC="${LOC_NAME[$i]}"
	REASON="Matched en0 IP"
	break
    elif [ -n "$EN1IP" && "$EN1IP" == "${LOC_EN1IP[$i]}" ]; then
	NEW_LOC="${LOC_NAME[$i]}"
	REASON="Matched en1 IP"
	break
    fi
    i=$(expr $i + 1)
done

# If we didn't find a configured location to match the current network
# state, fall back to Automatic.
if [ -z "$NEW_LOC" ]; then
    NEW_LOC="Automatic"
    REASON="No known locations detected"
fi

# At this point we have a decision as to what we want to do.
$LOGGER -p $INFOLOG "Selected $NEW_LOC as desired location."

# If the location isn't changing, do nothing.
if [ "$NEW_LOC" == "$CUR_LOC" ]; then
    $LOGGER -p $INFOLOG "Location has not changed. Reason: $REASON"
    exit 0
fi

# If the location is changing, figure out what we need to change it to
# and set the new location.
changed_loc=0
if [ "$NEW_LOC" == "Automatic" ]; then
    # We're switching to Automatic
    $LOGGER -p $INFOLOG "Setting Network Location $NEW_LOC"
    set_location $NEW_LOC
    changed_loc=1
else
    # We're switching to a different location as defined up top.
    i=0;
    while [ $i -lt ${#LOC_NAME[@]} ]; do
	if [ "$NEW_LOC" == "${LOC_NAME[$i]}" ]; then
	    $LOGGER -p $INFOLOG "Setting Network Location $NEW_LOC"
	    set_location $NEW_LOC
	    changed_loc=1
	    break
	fi
	i=$(expr $i + 1)
    done
fi

# Check the current location again to see if it's changed
CUR_LOC=
get_location CUR_LOC
$LOGGER -p $INFOLOG "Current location is now: $CUR_LOC"

# If we think we've changed network locations...
if [ $changed_loc -eq 1 ]; then

    # See if we really did change...
    if [ "$CUR_LOC" == "$NEW_LOC" ]; then

	# Yay, announce our success with pride!
	$GROWL -s -p2 -n "Auto Location" \
	    -a "/Applications/Utilities/Airport Utility.app/" \
	    -m "Updated Location: $NEW_LOC Reason: $REASON SSID: $SSID"

	$LOGGER -p $INFOLOG "Updated Location: $NEW_LOC; REASON: $REASON; SSID: $SSID"

    else

	# Boo, we completely failed, and need to tell someone.
	$GROWL -s -p2 -n "Auto Location" \
	    -a "/Applications/Utilities/Airport Utility.app/" \
	    -m "FAILED! Unable to update Location to $NEW_LOC! Reason: $REASON SSID: $SSID"

	$LOGGER -p $ERRLOG "FAILED! Unable to update Location to $NEW_LOC!"
    fi

fi

# vim: ft=sh sw=4
