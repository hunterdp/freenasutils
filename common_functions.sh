#!/bin/sh

#
# sect title
#	Display section title
#
sect()
{
	echo -e "${C_GREEN_S}${*}${C_GREEN_E}\n"
}

subsect()
{
	echo -e "${C_YELLOW_S}${*}${C_YELLOW_E}"
}

subsubsect()
{
	echo -e "${C_BOLD_S}${*}${C_BOLD_E}"
}

#
# info message
#	Display informational message to stdout.
#
info()
{
	if checkyesno INFO_MSGS; then
		echo -e "INFO: ${C_CYAN_S}${*}${C_CYAN_E}"
	fi
}

#
# err exitval message
#	Display message to stderr and exit with exitval.
#
err()
{
	local _exitval=$1
	shift

	echo -e 1>&2 "`basename $0`: ERROR: ${C_RED_S}${*}${C_RED_E}"
	exit $_exitval
}

#
# warn message
#	Display message to stderr.
#
warn()
{
	echo -e "WARNING: ${C_MAGENTA_S}${*}${C_MAGENTA_E}"
}

#
# debug message
#	If debugging is enabled in sysinfo.conf output message to stderr.
#
debug()
{
	# XXX: we cannot use checkyesno() here as we would end up with
	#      infinite loop.
	case $DEBUG in
	# "yes", "true", "on", or "1"
	[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
		echo -e 1>&2 "`basename $0`: DEBUG: ${C_BOLD_S}${*}${C_BOLD_E}"
		;;
	esac
}

#
# is_verbose level
#	Retrun 0 if VERBOSE level is greater or equal to level,
#	otherwise retrun 1.
#
is_verbose()
{
	debug "VERBOSE is set to ${VERBOSE}."

	if [ ${VERBOSE} -ge $1 ]; then
		return 0
	fi

	return 1
}

#
# is_root
#	Check whether current user is root.
#	Returns 0 if true, 1 otherwise.
#
is_root()
{
	if [ "$(id -u)" != "0" ]; then
		return 1
	else
		return 0
	fi
}

#
# is_jailed
#	Check whether this system is running from within a jail.
#	Retruns 1 if true, 0 otherwise.
#
is_jailed()
{
	return $(sysctl -n security.jail.jailed)
}

#
# check_privs path
#	Checks path whether exists and is readble
#
check_privs()
{
	if [ -r $1 ]; then
		return 0
	elif [ -e $1 ] && ! is_root; then
		warn "$1 is not readable!"
		warn "Running $0 as an unprivileged user may prevent some features from working."
	elif ! is_jailed; then
		warn "Running $0 from within a jail is not supported."
	fi

	return 1
}

#
# getsysconf
#	Reads the system configuration from system-wide
#	configuration files.
#
getsysconf()
{
	if [ -r /etc/defaults/rc.conf ]; then
		debug "Sourcing /etc/defaults/rc.conf"
		. /etc/defaults/rc.conf
		debug "Sourcing local system configuration files"
		source_rc_confs
	elif [ -r /etc/rc.conf ]; then
		debug "Sourcing /etc/rc.conf (/etc/defaults/rc.conf doesn't exist)."
		. /etc/rc.conf
		if [ -r /etc/rc.conf.local ]; then
			debug "Sourcing /etc/rc.conf.local"
		fi
	fi
}

#
# checkyesno var
#	Test $1 variable, and warn if not set to YES or NO.
#	Return 0 if it is "yes", 1 otherwise.
#
checkyesno()
{
	eval _value=\$${1}
	debug "checkyesno: $1 is set to $_value."

	case $_value in

		# "yes", "true", "on", or "1"
	[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|1)
		return 0
		;;

		# "no", "false", "off", or "0"
	[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0)
		return 1
		;;
	*)
		debug "\$${1} is not set properly: $_value."
		return 1
		;;
	esac
}

#
# getpciconf device type
#	Print information of specified type from pciconf related
#	to device.
#
getpciconf()
{
	local _device _type i

	_device=$1
	_type=$2
	i=5

	if check_privs /dev/pci;  then
		pciconf -lv | sed 's/ *= /=/' | while read line
		do
			if echo $line | grep -q "^${1}"; then
				i=$(( $i - 1 ))
			fi

			# Each device produces 4 lines of data
			if [ $i -ge 0 ] && [ $i -lt 5 ]; then
				for t in $_type; do
					echo $line | grep -w $t
				done
				i=$(( $i - 1 ))
			fi
		done
	fi
}
