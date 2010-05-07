#!/bin/bash
########################################################################
# Script:	ussd.sh
# Description:	Prototype of a GUI for gsm-ussd
# Author:	Jochen Gruse
# External dependencies:	(Package)
#		grep		(grep)
#		sed		(sed)
#		kdialog		(kdebase-bin)
#		qdbus		(libqt4-dbus)
#		zenity		(zenity)
#		gsm-ussd	(gsm-ussd)
########################################################################
# Copyright (C) 2010 Jochen Gruse, jochen@zum-quadrat.de
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
# 
########################################################################


########################################################################
# Support functions
########################################################################


########################################################################
# Function:	check_de
# Description:	Tries to divine which Desktop Environment we're running
#		under.
# Output:	"none" if not in X
#		"kde" if running in KDE
#		"gnome" if running in GNOME
#		"unknown" for everything else
function check_de {
	if [ -z "$DISPLAY" ] ; then
		echo none
	elif [ -n "$GNOME_DESKTOP_SESSION_ID" ] ; then
		echo gnome
	elif [ -n "$KDE_FULL_SESSION" ] ; then
		echo kde
	else
		echo unknown
	fi
	return 0
}


########################################################################
# Function:	check_binaries
# Description:	Checks each argument, if a program of that name can
#		be found in the PATH.
# Output:	Available programs are returned.
function check_binaries {
	local AVAILABLE=""

	for BINARY ; do
		if type -f "$BINARY" >/dev/null 2>&1 ; then
			AVAILABLE="$AVAILABLE $BINARY"
		fi
	done
	echo $AVAILABLE
}


########################################################################
# Function:	escape_markup
# Description:	Translates in its stdin
#		every & into &amp;
#		every < into &lt;
#		every > into &gt;
#		and writes the resulting text to stdout
function escape_markup {
	sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}


########################################################################
# KDE functions
########################################################################


########################################################################
# Function:	get_ussd_query_kde
# Description:	Creates a kdialog text box to enter the USSD query
function get_ussd_query_kde {
	kdialog \
	--title "$TITLE" \
	--inputbox 'Please enter the USSD query you would like to send:' '*100#' \
	2>&-
}


########################################################################
# Function:	get_pin_kde
# Description:	Creates a kdialog text box to enter the PIN
function get_pin_kde {
	kdialog \
	--title "$TITLE" \
	--password 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
	2>&-
}


########################################################################
# Function:	show_progressbar_kde
# Description:	Fakes a "progress" bar.
#		You'll see progress every second. This function will
#		not end by itself, but has to be killed from outside,
#		so only start it in the background.
#		If the progressbar reaches 100% before being kill, it
#		will slowly decrease back to 0% and begin again.
#		Too bad that kdialog does not have a "--pulsate" option
#		like zenity does!
function show_progressbar_kde {
	local -i MAX=20
        local -i COUNT=0
	local -i STEP=1

        local DBUS_REF=$(
		kdialog \
		--title "$TITLE" \
		--progressbar "Query running..." \
		$MAX \
		2>&-
	)

        trap 'qdbus $DBUS_REF close >/dev/null 2>&1; return 0' 0 15

        while : ; do
		(( COUNT += STEP ))
                qdbus $DBUS_REF Set "" "value" $COUNT >/dev/null 2>&1
		(( COUNT >= MAX )) && (( STEP = -STEP ))
                sleep 1
        done

	return 0
}


########################################################################
# Function:	show_result_kde
# Description:	Creates a kdialog info box to show the USSD query result
function show_result_kde {
	if [ "$1" -ne 0 ] ; then
		local DIALOG_TYPE="--error"
	else
		local DIALOG_TYPE="--msgbox"
	fi
	kdialog --title "$TITLE" $DIALOG_TYPE "$2"
}


########################################################################
# GNOME functions
########################################################################


########################################################################
# Function:	get_ussd_query_gnome
# Description:	Creates a zenity text box to enter the USSD query
function get_ussd_query_gnome {
	zenity \
	--title "$TITLE" \
	--entry \
	--text 'Please enter the USSD query you would like to send:' \
	--entry-text '*100#' \
	2>&-
}


########################################################################
# Function:	get_pin_gnome
# Description:	Creates a zenity text box to enter the PIN
function get_pin_gnome {
	zenity \
	--title "$TITLE" \
	--entry \
	--text 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
	--hide-text \
	2>&-
}


########################################################################
# Function:	show_progressbar_gnome
# Description:	Fakes a "progress" bar.
function show_progressbar_gnome {

	
        trap 'kill $ZENITY_PID; return 0' 0 2 15

	while : ; do		# Poor man's "yes" B^)
		echo "y"
		sleep 1
	done | \
	zenity \
		--title "$TITLE" \
		--progress \
		--pulsate &
	ZENITY_PID=$!

	wait			# Will not return by itself, must be
				# killed!
	return 0
}


########################################################################
# Function:	show_result_gnome
# Arguments:	$1 - Exit code of gsm-ussd
#		$2 - Message to display
# Description:	Creates a zenity info box to show the USSD query result
function show_result_gnome {
	if [ "$1" -ne 0 ] ; then
		local DIALOG_TYPE="--error"
	else
		local DIALOG_TYPE="--info"
	fi
	zenity --title "$TITLE" $DIALOG_TYPE --text "$(echo "$2" | escape_markup )"
}


########################################################################
# MAIN
########################################################################

# Name of this script, used in dialog titles
TITLE=${0##*/}

# Any options are given over to gsm-ussd. No checking done here!
GSM_USSD_OPTS="$@"

SUPPORTED_DIALOG_TOOLS="kdialog zenity"

# Which DE are we running under?
DESKTOP=$(check_de)
AVAILABLE_DIALOG_TOOLS=$(check_binaries $SUPPORTED_DIALOG_TOOLS)

case $DESKTOP in 
none)	# No X11, use command line program
	# One might try dialog or whiptail, but in this case isn't it 
	# better to just use gsm-ussd directly?
	exec gsm-ussd $GSM_USSD_OPTS
	# NOTREACHED
	;;
unknown)
	# Something else than GNOME/KDE, find what's available
	if echo "$AVAILABLE_DIALOG_TOOLS" | grep -q kdialog; then
		DESKTOP=kde
	elif echo "$AVAILABLE_DIALOG_TOOLS" | grep -q zenity; then 
		DESKTOP=gnome
	else
		# No supported dialog tool found, fall back to
		# CLI version
		exec gsm-ussd $GSM_USSD_OPTS
		# NOTREACHED
	fi
	;;
esac


# -p/--pin already given? Then we don't have to ask by dialog box
# This is only an approximation, the legal grouping
#	-cdp 1234
# is not recognized
PIN_NEEDED=1
if echo "$GSM_USSD_OPTS" | grep -Eq -- '-p|--pin' ; then
	PIN_NEEDED=0
fi

# Ask for USSD query, set "*100#" as default
USSD_QUERY=$( get_ussd_query_$DESKTOP )
if [ $? -ne 0 ] ; then
	exit 1
fi

# Ask for PIN, if needed
PIN_OPT=""
if [ $PIN_NEEDED -eq 1 ] ; then
	PIN=$( get_pin_$DESKTOP)
	if [ $? -eq 0 -a -n "$PIN" ] ; then
		PIN_OPT="-p $PIN"
	fi
fi

# Start the progress bar display
show_progressbar_$DESKTOP &
PROGRESS_PID=$!

# Do the actual work
RESULT=$( gsm-ussd $PIN_OPT $GSM_USSD_OPTS "$USSD_QUERY" 2>&1 )
GSM_USSD_EXITCODE=$?

# End progress bar display (if not already gone)
kill $PROGRESS_PID >&- 2>&-

# Show gsm-ussd result in appropiate dialog box
show_result_$DESKTOP "$GSM_USSD_EXITCODE" "$RESULT"

exit 0