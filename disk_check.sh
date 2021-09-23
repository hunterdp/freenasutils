#!/bin/bash
#   A simple script to collect some information about the disks on a Linux,
#   FreeBSD or NetBSD server.  The data is stored in a file and optionally emailed.
#   The most complete functions are for a FreeBSD system, as it was originally
#   developed for FreeNAS reporting.  The script needs to have root privs.
#
# Prerequisites:
#  - smartmon tools must be installed in order to use smartctl
#  - mmc-utils if host has eMMC cards
#####

## Notes:
# TODO(dph) - Need to add capability to read SD cards (raspberry pi)  Info is located at
#             sys/block/mmcblk#.  Also can try the udevadm -a -c /dev/mmcblk# command
# TODO(dph) - Need to add ability to get information about virtual disks
# TODO(dph) - Check to see if the script needs to be run as sudo or root
# TODO(dph) - Change up all functions so globals are passed in versus assumed.
# TODO(dph) - Add error checking for function calls instead of just calling die.
# TODO(DPH) - Make these environmental variables.
#
#
set -o nounset # Exposes unset variables

##### Constants #####
declare -r AUTHOR="David Hunter"
declare -r VERSION="Version 0.6 beta"
declare -r PROG_NAME="disk_check.sh"
declare -r TRUE="YES"
declare -r FALSE="NO"
declare -r -i FAILURE=1
declare -r -i SUCCESS=0
declare -r -i BASH_REQ_MAJ_VER=4
declare -r -i BASH_REQ_MIN_VER=0
declare -r -i BASH_MAJ_VER=${BASH_VERSINFO[0]}
declare -r -i BASH_MIN_VER=${BASH_VERSINFO[1]}

# Required commands and optional commands.  The script will not function
# without required commands.  The script MAY function without an optional command.
declare -a REQ_CMDS="awk uname hostname smartctl uptime hostname hash wc"
declare -a OPT_CMDS="sysctl geom lsblk dmidecode lshw blkid pr column zpool"
declare -a REQ_LINUX_CMDS="sensors"
declare -a ALL_CMDS="$REQ_CMDS $OPT_CMDS $REQ_LINUX_CMDS"

##### Global Variables #####
declare -g -l DEBUG="n"
declare -g -l MAIL_FILE="declare -g -l"
declare -g -l O_FILE="/tmp/disk_overview.txt"
declare -g EMAIL_TO="user@company.com"
declare -g -l HOST_NAME=$(hostname -f)
declare -g MAIL_SUBJECT="SMART and Disk Summary for $HOST_NAME on $(date)"

# An assoicative array (sometimes called a dictionary) that holds system commands and if
# they are available on the system.  This will get filled in the commands are tested. The
# value for each key is either the global TRUE or FALSE.
declare -g -A LIST_OF_COMMANDS

# An associative array of disks.  Key is name of device and value is device type.  For
# example LIST_OF_DISKS[da0]=HDD
declare -g -A LIST_OF_DISKS

# An associative array of system attributes and their values.  K/V pairs are
# added onto (aka: multiple CPU stats).  Use a consistent naming prefix such that
# the array can be sorted on major sections.
declare -g -A SYS_INFO

# An associative array that contains a listing of available zppols and their
# status.
declare -g -A LIST_OF_ZPOOLS

function log_info() {
  #######################################
  # Description:
  #   Pretty prints out information to standard output.
  # Globals:
  #    DEBUG
  # Arguments:
  #   $0  filename
  #   $1  Message to output
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local file_name=$0
  local src_line=${BASH_LINENO}
  local -u severity="INFO"
  local mesg=$1
  declare call_stack
  call_stack=$(dump_stack 2)
  if [ $DEBUG == "y" ]; then
    printf "%(%m-%d-%Y %H:%M:%S)T %-20s %-75s %-5s %s\n" $(date +%s) "$file_name" \
      "$call_stack" "$severity" "$mesg"
  fi
  return $SUCCESS
}

function log_error() {
  #######################################
  # Description:
  #   Pretty prints out information to standard error.
  # Globals:
  #    DEBUG
  # Arguments:
  #   $0  filename
  #   $1  Message to output
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local file_name=$0
  local src_line=${BASH_LINENO}
  local -u severity="ERROR"
  local mesg=$1
  declare call_stack
  call_stack=$(dump_stack 2)
  if [ $DEBUG == "y" ]; then
    printf "%(%m-%d-%Y %H:%M:%S)T %-20s %-75s %-5s %s\n" $(date +%s) "$file_name" \
      "$call_stack" "$severity" "$mesg" >&2
  fi
  return $SUCCESS
}

function log_info_array() {
  #######################################
  # Description:
  #   Given an associative array, print out the key-pair
  #   using the log_info function.
  # Globals:
  #    None
  # Arguments:
  #   $1  Array
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local key
  local -n keys=$1
  for key in ${!keys[@]}; do
    log_info "$key : ${keys[$key]}"
  done
  return $SUCCESS
}

function echo_info_array() {
  #######################################
  # Description:
  #   Given an associative array, print out the key-pair
  # Globals:
  #    None
  # Arguments:
  #   $1  Array
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local key
  local -n keys=$1
  for key in ${!keys[@]}; do
    echo -n "[$key : ${keys[$key]}] "
  done
  echo ""

  return $SUCCESS
}

function dump_stack() {
  #######################################
  # Description:
  #   A simple call stack dumper.  The passed in parameter indicates which
  #   level of the stack to start at.  Normally you would start at level 1,
  #   which will not include the "dump_stack" function itself.  For calling from
  #   a debugging function, start at level 2 to not include the logging function.
  # Globals:
  #   None
  # Arguments:
  #   $1  The function level to start at
  # Returns:
  #   A one dimmension array of the function stack
  # Notes:
  #######################################
  local -i i
  local -i start_level=$1
  local -a stack ret_stack
  for ((i = start_level; i < ${#FUNCNAME[*]}; i++)); do
    printf -v stack[$i] "%s" "${FUNCNAME[$i]}(${BASH_LINENO[$i - 1]})."
  done

  # remove the trailing "."
  printf -v ret_stack "%s" "${stack[@]}"
  printf ${ret_stack%.*}
}

function die() {
  #######################################
  # Description:
  #   Prints out the full call stack and then exits.
  # Globals:
  #    None
  # Arguments:
  #   msg             str
  #   call_frame_dump bool
  # Returns:
  #   $FAILURE
  # Notes:
  #######################################
  local -i frame=0
  local msg
  msg=$1
  if [ $# == 2 ]; then
    call_stack=$2
    log_info "$msg"
    log_info "Dumping call stack.."

    while caller $frame; do
      ((frame++))
    done
  fi

  exit $FAILURE
}

function usage() {
  #######################################
  # Description:
  #   Pretty prints out the command usage.
  # Globals:
  #    None
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS
  # Notes:
  #######################################
  cat <<EOF
  Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y | n] [-s subject] [-o html | text]
     where:
       -d                             turn on debug
       -e email_address               email address to send the file to
       -f filename                    filename to save info to (default /tmp/disk_overview.txt)
       -m y|n                         mail the file or not
       -s subject                     subject of email
       -v                             prints out version of program
       -z                             prints out information on zpools if available

   Prerequisites:
    - smartmon tools must be installed in order to use smartctl
    - mmc-utils if host has eMMC cards
EOF
  exit $SUCCESS
}

function get_cmd_args() {
  #######################################
  # Description:
  #   Parses command options and sets globals
  # Globals:
  #    DEBUG
  #    EMAIL_TO
  #    O_FILE
  #    MAIL_FILE
  #    EMAIL_SUBJECT
  #    PROG_NAME
  #    AUTHOR
  # Arguments:
  #   $* Command line arguments
  # Returns:
  #   $SUCCESS
  # Notes:
  #   TODO(dph): Switch to using a key-pair array for all global options.
  #
  #######################################
  local passed_args="$*"
  local getopts
  while getopts 'vhde:f:m:s:z:' arg; do
    case $arg in
    d)
      DEBUG="y"
      ;;
    e)
      EMAIL_TO="$OPTARG"
      ;;
    f)
      O_FILE="$OPTARG"
      ;;
    h | \?)
      usage
      ;;
    m)
      MAIL_FILE="$OPTARG"
      ;;
    s)
      EMAIL_SUBJECT="$OPTARG"
      ;;
    z)
      ZPOOL="$OPTARG"
      ;;
    v)
      printf "%s\n" "$PROG_NAME: $VERSION by $AUTHOR."
      exit $SUCCESS
      ;;
    esac
  done
  shift "$((OPTIND - 1))"
  log_info "Command line arugments passed were: $passed_args."
}

function check_file_exist() {
  #######################################
  # Description:
  #   Checks for the existance of a file and returns success or failire
  # Globals:
  #    None
  # Arguments:
  #   $1  File to check for
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local -r file="${1}"
  if [[ "${file}" = '' || ! -f "${file}" ]]; then
    return $FAILURE
  else
    return $SUCCESS
  fi
}

function check_paramcondition() {
  #######################################
  # Description:
  #   Give a parameter, its warnning and error will return the
  #   param in a color code according to warnd, error or good.
  # Globals:
  #    None
  # Arguments:
  #   $1 Parameter to check
  #   $2 Warning threshold
  #   $3 Error threshold
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local param_to_check=$1
  local param_warn=$2
  local param_err=$3
}

function validate_commands() {
  #######################################
  # Description:
  #   Given an array with a set of commands, if any are
  #   not available, exit the program.
  # Globals:
  #    None
  # Arguments:
  #   $1  Array of commands to check
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local command
  for command in $1; do
    if ! hash "$command" >/dev/null 2>&1; then
      log_error "Required command $command not availabe.  Exiting the program."
      return $FAILURE
    fi
  done
  return $SUCCESS
}

function check_avail_commands() {
  #######################################
  # Description:
  #   Looks to see if the commands in the array passed are available on the system
  #   and stores the results in the passed associative array
  # Globals:
  #    LIST_OF_COMMANDS
  #    DEBUG
  # Arguments:
  #   $1  Array of commands to check
  #   $2  Message to output
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #   TODO(dph): Update to use a passed in key-pair array vs a global
  #######################################
  local cmds_missing=0
  local cmd k
  declare -A commands_to_check=$1
  #  declare -n command_array=$2

  for cmd in $commands_to_check; do
    LIST_OF_COMMANDS["$cmd"]=$TRUE
    if ! hash "$cmd" >/dev/null 2>&1; then
      LIST_OF_COMMANDS["$cmd"]=$FALSE
      ((cmds_missing++))
    fi
  done
  if ((cmds_missing > 0)); then
    log_info "$cmds_missing commands are missing or not in PATH."
  fi
  if [ $DEBUG == "y" ]; then log_info_array LIST_OF_COMMANDS; fi
  return $SUCCESS
}

function is_command_available() {
  #######################################
  # Description:
  #   Checks the passed command and sees if it is listed as available
  # Globals:
  #   DEBUG
  #   LIST_OF_COMMANDS
  # Arguments:
  #   $1  command to check for
  # Returns:
  #  Returns $SUCCESS if available or $FAILURE if not found or not available
  # Notes:
  #   TODO(dph): Change to use in a passed array vs a global
  #######################################
  local i
  local command_to_check_for=$1
  log_info "Checking on status of $1 command."
  for i in ${!LIST_OF_COMMANDS[*]}; do
    if [[ $command_to_check_for == $i ]]; then
      if [[ $TRUE == ${LIST_OF_COMMANDS[$i]} ]]; then
        log_info "$command_to_check_for is available ==> ${LIST_OF_COMMANDS[$i]}."
        return $SUCCESS
      else
        log_info "$command_to_check_for is available but not working. ==> ${LIST_OF_COMMANDS[$i]}."
        return $FAILURE
      fi
    fi
  done
  log_info "$command_to_check_for is not available."
  return $FAILURE
}

#####  Storage Related  #####
function get_disks() {
  #######################################
  # Description:
  #   Gets the disk on the system.  It tries to get the most accurate and comprehensive
  #   list of disks depending upon the commands available on the machine.  It stores the
  #   disks found and their type in a sorted global array, LIST_OF_DISKS.
  # Globals:
  #   DEBUG
  #   LIST_OF_DISKS
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #   TODO(dph): Switch to move away from global LIST_OF_DISKS
  #######################################
  local -a disks
  local device
  local i
  local key
  local keys
  # Use the best command for discovery.  The list is in what I believe
  # the best chance of getting the most disks.
  if is_command_available lsblk; then
    log_info "Using the lsblk command to obtain disks on the system."
    disks=$(lsblk -dp | grep -o '^/dev[^ ]*' | sed 's/\/dev\///')
    #    disks=$(lsblk --nodeps --noheadings --output name,type --scsi | awk {'print $1'})
  elif is_command_available sysctl; then
    log_info "Using sysctl command to obtain disks on the system."
    disks=$(sysctl -n kern.disks)
  elif is_command_available geom; then
    log_info "Using geom command to obtain disks on the system."
    disks=$(geom disk list | grep Name | awk '{print $3}')
  else
    log_info "ERROR" "Unable to find a command to get disks.  Aborting."
    err "Unable to find a command to get disks. Aborting."
    exit $FAILURE
  fi

  # Remove carriage returns and sort the array and then for each
  # disk, get its type and store inthe global array of disks
  disks=$(sort <<<"${disks[*]}")
  disks=$(echo "$disks" | tr '\n' ' ')
  log_info "Array of disks found: $disks"

  for device in $disks; do
    LIST_OF_DISKS[$device]=$(get_disk_type "$device")
  done
  log_info "The number of disks in the array are: ${#LIST_OF_DISKS[@]}"
  # Dump out the LIST_OF_DISK Dictionary but first sort by key name
  # to make reading a bit easier.
  if [ $DEBUG == "y" ]; then
    keys=$(echo ${!LIST_OF_DISKS[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
    log_info "Dumping the LIST_OF_DISKS Dictionary..."
    log_info_array LIST_OF_DISKS
  fi
  return $SUCCESS
}

function get_disk_type() {
  #######################################
  # Description:
  #   Given a disk device, return (via printing it) the type of disk
  #   Calling method is via =$(get_disk_type disk)
  # Globals:
  #   None
  # Arguments:
  #   $1  Disk to check
  # Returns:
  #   Type of disk
  # Notes:
  #   TODO(dph): Think about shifting this to use the syslog
  #######################################
  local disk=$1
  local dev_type
  local results=$(smartctl -i /dev/$disk)
  local ssd=$(grep 'Solid State Device' <<<$results)
  local usb=$(grep 'USB bridge' <<<$results)
  local offline=$(grep 'INQUIRY failed' <<<$results)
  local vmware=$(grep 'VMware' <<<$results)
  local hdd=$(grep 'rpm' <<<$results)

  if [[ -n "${ssd/[ ]*\n/}" ]]; then
    dev_type="SSD"
  elif [[ -n "${usb/[ ]*\n/}" ]]; then
    dev_type="USB"
  elif [[ -n "${offline/[ ]*\n/}" ]]; then
    dev_type="OFFLINE"
  elif [[ -n "${vmware/[ ]*\n/}" ]]; then
    dev_type="VMWare"
  elif [[ -n "${hdd/[ ]*\n/}" ]]; then
    dev_type="HDD"
  else
    dev_type="UKN"
  fi
  printf "%s\n" $dev_type
  return $SUCCESS
}

function clear_array_values() {
  #######################################
  # Description:
  #   Takes as input an associative array and clears the values for each key
  #   Note that this does not unset the key-pair, just clears the value
  # Globals:
  #   None
  # Arguments:
  #   $1  Array to clear
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #   TODO(dph): Think about shifting this to use the syslog
  #######################################
  # the keys found.
  local key
  local -n keys=$1
  log_info "Clearing: ${#keys[@]} key pair values."
  for key in ${!keys[@]}; do
    disk_info[$key]=""
  done
  return $SUCCESS
}

function print_disk_info() {
  #######################################
  # Description:
  #   Given an associative array, print out its contents the file specified.
  # Globals:
  #   None
  # Arguments:
  #   $1 Array to output
  #   $2 Name of the file to output to
  #   #3 Type of output (html or text)
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local val
  local -n vals=$1
  local fmt="| %-10.10s "
  local pretty_val
  local output_file=$2
  # We have the list of disk and disk types in associative array as it should be prefixed by
  # a letter in the  alphabetical order to be printed. Do this by creating an index array of
  # the indexes, sort that array and use it to itterate through the passed array
  keys=$(echo ${!vals[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
  for key in $keys; do
    pretty_val=$(echo "${vals[$key]}" | tr '\n' ' ')
    printf "$fmt" "${vals[$key]}" >>$output_file
  done
  printf "|\n" >>$output_file
  return $SUCCESS
}

function get_disk_info() {
  #######################################
  # Description:
  #   Cycle thrrough the disks and collect information about the
  #   disk and print it out.
  # Globals:
  #    LIST_OF_DISKS
  #    O_FILE
  # Arguments:
  #   $0  filename
  #   $1  Message to output
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local i
  local j
  local key
  local -a keys
  declare -A disk_info=(
    [a_device]=
    [b_type]=
    [c_model]="-"
    [d_ser_num]="-"
    [e_capacity]="-"
    [f_temp]="-"
    [g_cur_speed]="-"
    [i_pwr_on_hrs]="-"
    [j_start_stop_ct]="-"
  )

  # Create an index array of the indexes, sort it and use it to itterate through the global array
  keys=$(echo ${!LIST_OF_DISKS[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
  for key in $keys; do
    # Clear all the key values to avoid unset or unfound values on particular disks.
    clear_array_values disk_info
    log_info "Examing device $key which is ${LIST_OF_DISKS[$key]} device."

    # For each of the device types, collect those common SMART values. More details are
    # available at https://en.wikipedia.org/wiki/S.M.A.R.T. and
    # https://wiki.unraid.net/Understanding_SMART_Reports
    disk_info[a_device]="$key"
    disk_info[b_type]="${LIST_OF_DISKS[$key]}"
    case ${LIST_OF_DISKS[$key]} in
    HDD | SSD)
      full_results=$(smartctl -a /dev/$key)
      disk_info[c_model]=$(grep 'Device Model' <<<$full_results | awk '/Device Model/          {print $3 $4}')
      disk_info[d_ser_num]=$(grep 'Serial Number' <<<$full_results | awk '/Serial Number/         {print $3}')
      disk_info[e_capacity]=$(grep 'User Capacity' <<<$full_results | awk '/User Capacity/         {print $5, $6}' | sed -e 's/^.//' -e 's/.$//')
      disk_info[f_temp]=$(grep 'Temperature_Celsius' <<<$full_results | awk '/Temperature_Celsius/   {print $10}')
      disk_info[g_cur_speed]=$(grep 'SATA Version' <<<$full_results | awk '/SATA Version/          {print $9, substr($10, 1, length($10)-1)}')
      disk_info[i_pwr_on_hrs]=$(grep 'Power_On_Hours' <<<$full_results | awk '/Power_On_Hours/        {print $10}')
      disk_info[j_start_stop_ct]=$(grep 'Start_Stop_Count' <<<$full_results | awk '/Start_Stop_Count/      {print $10}')
      ;;

    SSD) ;;

    \
      VMW) ;;

    \
      USB)
      full_results=$(smartctl -a -d scsi /dev/$key)
      disk_info[c_model]=$(grep 'Product' <<<$full_results | awk '/Product/ {print $2, $3, $4}')
      disk_info[e_capacity]=$(grep 'User Capacity' <<<$full_results | awk '/User Capacity/ {print $5, $6}' | sed -e 's/^.//' -e 's/.$//')
      disk_info[d_ser_num]=$(grep 'Vendor:' <<<$full_results | awk '/Vendor:/ {print $3}')
      disk_info[j_start_stop_ct]=$(grep 'Power_Cycle_Count' <<<$full_results | awk '/Power_Cycle_Count/ {print $10}')
      ;;

    OFFLINE)
      log_info "Disk is offline."
      ;;

    UKN)
      log_info "Unknown disk type"
      ;;
    esac
    log_info_array disk_info
    print_disk_info disk_info "${O_FILE}"
  done
  draw_separator "=" 118
  return $SUCCESS
}

function print_zpool_info() {
  #######################################
  # Description:
  #   Prints out zpool information.
  # Globals:
  #    LIST_OF_ZPOOLS
  #    O_FILE
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS
  # Notes:
  #   TODO(dph): Remove dependency on globals
  #######################################
  local key
  printf "\n==============================\n" >>"${O_FILE}"
  printf "      ZFS Pool Information      \n" >>"${O_FILE}"
  printf "==================================\n" >>"${O_FILE}"
  printf "%s\n" "${LIST_OF_ZPOOLS[HEADER]}" |
    awk '{printf "%-20.20s %10.10s %10.10s %10.10s %10.10s %10.10s %10.10s %10.10s\n", \
                        $1,$2,$3,$4,$5,$6,$7,$8}' >>"${O_FILE}"
  draw_separator "=" 97
  for key in ${!LIST_OF_ZPOOLS[@]}; do
    if [[ $key != "HEADER" ]]; then
      printf "%s\n" "${LIST_OF_ZPOOLS[$key]}" |
        awk '{printf "%-20.20s %10.10s %10.10s %10.10s %10.10s %10.10s %10.10s %10.10s\n", \
                             $1,$2,$3,$4,$5,$6,$7,$8}' >>"${O_FILE}"
    fi
  done
  draw_separator "=" 118
  return $SUCCESS
}

function get_zpool_info() {
  #######################################
  # Description:
  #   Retrieves basic information about ZFS pools on the systems and stores
  #   them into the array passed.
  # Globals:
  #    DEBUG
  # Arguments:
  #   $1 Array to store the list into
  #   $1  Message to output
  # Returns:
  #   pool_info K/V pair array
  # Notes:
  #######################################
  local pool_list
  local pool
  declare -n pool_info=$1

  pool_list=$(zpool list -H -o name)
  pool_list=$(sort <<<"${pool_list[*]}")
  pool_list=$(echo "$pool_list" | tr '\n' ' ')
  log_info "Zpools found : ${pool_list[@]}"
  pool_info[HEADER]="$(zpool list -o name,size,alloc,free,frag,cap,dedup,health | head -1)"
  for pool in $pool_list; do
    pool_info[$pool]="$(zpool list -H -o name,size,alloc,free,frag,cap,dedup,health $pool)"
  done
}

function get_zpool() {
  #######################################
  # Description:
  #   Gets a list of the zpools on the system and returns it
  #   To call use x=$(get_zpools [pool]) to store into an array
  # Globals:
  #   None
  # Arguments:
  #   $1  pool to get information about [optiona]
  # Returns:
  #   The name of the pool or all pools if non passed
  # Notes:
  #######################################
  local pool=$1
  declare -a pool_list
  pool_list=$(zpool list -H -o name)
  log_info "Number of pools was ${#pool_list}"
  if [[ -z $pool ]]; then
    printf "%s" "$(zpool list -H -o name)"
  else
    printf "%s" "$(zpool list -H -o name $pool)"
  fi
}

function check_zpool_errors() {
  #######################################
  # Description:
  #   Issues the status command to check zpools for errors
  # Globals:
  #   None
  # Arguments:
  #   None
  # Returns:
  #   None
  # Notes:
  #######################################
  printf "\n==============================\n" >>"${O_FILE}"
  printf "      ZFS Pool Errors           \n" >>"${O_FILE}"
  printf "==================================\n" >>"${O_FILE}"
  printf "%s\n" "$(zpool status -x -v)" >>"${O_FILE}"

}

#####  System related functions #####
function get_cpu_info() {
  #######################################
  # Description:
  #   Retrieves varous infomation about the CPU and stores it in the
  #   SYS_INFO global array
  # Globals:
  #   SYS_INFO
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS
  # Notes:
  #######################################
  SYS_INFO[CPU_ARCH_TYPE]=$(uname -m)
  SYS_INFO[CPU_PROC_TYPE]=$(uname -p)

  if [[ -z ${SYS_INFO[OS_TYPE]} ]]; then
    log_info "OS_TYPE not defined.  Calling get_os_info"
    get_os_info
  fi
  log_info "Checking for cpu count under ${SYS_INFO[OS_TYPE]}"
  case ${SYS_INFO[OS_TYPE]} in

  FreeBSD)
    SYS_INFO[CPU_NUMBER]=$(sysctl -n hw.ncpu)
    SYS_INFO[CPU_MODEL]=$(sysctl -n hw.model)
    SYS_INFO[HOST_PHYS_MEM]=$(sysctl -n hw.physmem)
    ;;

  Linux)
    SYS_INFO[CPU_NUMBER]=$(grep -c '^processor' /proc/cpuinfo)
    SYS_INFO[CPU_CORE_COUNT]=$(grep -c '^cpu cores' /proc/cpuinfo)
    SYS_INFO[CPU_MODEL]=$(cat /proc/cpuinfo | grep 'model name' | head -1 | awk 'BEGIN {FS=":"}; {print $2}' | sed -e 's/^[ \t]*//')
    SYS_INFO[HOST_PHYS_MEM]=$(grep 'MemTotal' /proc/meminfo | grep 'MemTotal' | awk 'BEGIN {FS=":"}; {print $2}' | sed -e 's/^[ \t]*//')
    ;;
  esac
  log_info "Number of cpus found is: ${SYS_INFO[CPU_NUMBER]}"
  return $SUCCESS
}

function get_hw_info() {
  #######################################
  # Description:
  #   Retrieve various hardware related information and store in the KV array
  # Globals:
  #   None
  # Arguments:
  #  none
  # Returns:
  #   $SUCCESS
  # Notes:
  #   TODO(dph): Implement
  #######################################

  return $SUCCESS
}

get_bios_info() {
  #######################################
  # Description:
  #   Retrieve information about the bios.  the dmidecode command is requried.
  # Globals:
  #   None
  # Arguments:
  #  none
  # Returns:
  #   $SUCCESS
  # Notes:
  #   TODO(dph): Implement
  #######################################

  SYS_INFO[BIOS_VENDOR]=$(dmidecode -s bios-vendor)
  SYS_INFO[BIOS_VERSION]=$(dmidecode -s bios-version)
  SYS_INFO[BIOS_REL_DATE]=$(dmidecode -s bios-release-date)
  SYS_INFO[FIRMWARE_REV]=$(dmidecode -s firmware-revision)
  return $SUCCESS
}

function get_temps() {
  #######################################
  # Description:
  #   Get temperatures of various elements (board, cpu, etc.)
  #   and add to SYS_INFO array
  # Globals:
  #   SYS_INFO
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS
  # Notes:
  #   TODO(dph): Add raspberry pi implementation
  #######################################
  local i
  local -i num_cpu_temps=0
  local cpu_temps

  case ${SYS_INFO[OS_TYPE]} in
  FreeBSD)
    # When called it will return an array of temps depending upon the ncpus
    # Store all the temps in SYS_INFO[CPU_TEMP] and then add individual temps to dictionary
    cpu_temps=($(sysctl -a | grep temperature | awk '{print $2}'))
    if [[ ${#cpu_temps[@]} -gt 0 ]]; then
      SYS_INFO[CPU_TEMP]="${cpu_temps[@]}"
      for i in "${cpu_temps[@]}"; do
        SYS_INFO[CPU_TEMP_$num_cpu_temps]=${cpu_temps[num_cpu_temps]}
        log_info "CPU number [$num_cpu_temps] temperature is: ${SYS_INFO[CPU_TEMP_$num_cpu_temps]}."
        ((num_cpu_temps++))
      done
    else
      SYS_INFO[CPU_TEMP]="0.0"
      log_info "CPU temperature not found."
    fi
    ;;

  Linux)
    SYS_INFO[HOST_CORE_TEMP]="$(sensors | grep 'Core 0' | awk '{print $3}')"
    CPU_TEMP=0
    ;;
    # For raspberry pi use /opt/vc/bin/vcgencmd measure_temp
  esac
  return $SUCCESS
}

function get_host_info() {
  #######################################
  # Description:
  #   Retrieves infomration about the system and stores it into the SYS_INFO dictionary
  # Globals:
  #   SYS_INFO
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #   TODO(dph): Separate network gathering into a new function
  #######################################
  local ip_addrs
  local -i num_ip_addrs=0
  local i

  SYS_INFO[HOST_NAME]=$(hostname -f)
  SYS_INFO[HOST_SHORT_UPTIME]=$(uptime | awk '{ print $3, $4, $5 }' | sed 's/,//g' | sed 's/\r//g')
  SYS_INFO[HOST_UPTIME]=$(uptime)

  ip_addrs=($(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'))
  log_info "Number of host ip addresses found is: ${#ip_addrs[@]}."
  SYS_INFO[HOST_IP_NUMBER]=${#ip_addrs[@]}
  # A system may have more than 1 ip address or interface.  Count the number and create an array with the ips.
  # We store all the ips found in HOST_IP and if more than 1, add unique SYS_INFO[HOST_IP_x] for each.
  if [[ ${#ip_addrs[@]} -gt 0 ]]; then
    SYS_INFO[HOST_IP]=${ip_addrs[@]}
    for i in "${ip_addrs[@]}"; do
      SYS_INFO[HOST_IP_$num_ip_addrs]=${ip_addrs[num_ip_addrs]}
      log_info "IP address number [$num_ip_addrs] found is: ${SYS_INFO[HOST_IP_$num_ip_addrs]}."
      ((num_ip_addrs++))
    done
  else
    SYS_INFO[HOST_IP]="0.0.0.0"
    log_info "IP address not found, setting to ${SYS_INFO[HOST_IP]}."
  fi

  SYS_INFO[PRODUCT_NAME]=$(dmidecode -s system-product-name)
  SYS_INFO[MANUFACURER]=$(dmidecode -s system-manufacturer)
  SYS_INFO[SYS_SERIAL_NUM]=$(dmidecode -s system-serial-number)
  SYS_INFO[SYSTEM_VERSION]=$(dmidecode -s system-version)

  return $SUCCESS
}

function get_os_info() {
  #######################################
  # Description:
  #   Stores  info about the operating system in the SYS_INFO dictionary
  # Globals:
  #   SYS_INFO
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  SYS_INFO[OS_TYPE]=$(uname -s)
  SYS_INFO[OS_VER]=$(uname -o)
  SYS_INFO[OS_REL]=$(uname -r)
  return $SUCCESS
}

function get_sys_info() {
  #######################################
  # Description:
  #   Collects various system information  and stores it in the global array.
  #   If KV pair not found, it will assume its a new one andpopo it onto
  #   the array.  For each value, we want to utilize a function to fill in the
  #   key-pair to allow for portability.  Ensure we collect any variables that
  #   are used to make decisions early (OS_TYPE, ARCH_TYPE, PROC_TYPE).
  # Globals:
  #   SYS_INFO
  #   DEBUG
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local key
  local -a keys

  get_hw_info
  get_os_info
  get_bios_info
  get_cpu_info
  get_host_info
  get_temps

  if [ $DEBUG == "y" ]; then
    local keys=$(echo ${!SYS_INFO[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
    log_info "Dumping the SYS_INFO Dictionary..."
    log_info_array SYS_INFO
  fi
  return $SUCCESS
}

function print_sys_info() {
  #######################################
  # Description:
  #   Prints out simple system information.  This simply dumps the
  #   keys and values in the SYS_INFO array
  # Globals:
  #   SYS_INFO
  #   O_FILE
  # Arguments:
  #   None
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local key
  local -a keys

  local keys=$(echo ${!SYS_INFO[@]} | tr ' ' '\012' | sort | tr '\012' ' ')
  local fmt="%-60.60s%-60.60s%60.60s\n"
  printf "%s\n" "============================" >>${O_FILE}
  printf "%s\n" "    System Information" >>$O_FILE
  printf "%s\n" "============================" >>${O_FILE}
  for key in $keys; do
    printf "%-25s %-25s\n" "$key:" "${SYS_INFO[$key]}"
  done | column >>${O_FILE}
  draw_separator "=" 118
  return $SUCCESS
}

##### Some simple text based Output Functions #####
function draw_separator() {
  #######################################
  # Description:
  #   Given a character and number, it prints out the character n times.  Do
  #   not pass the "-" character or a number.  Basically anything that would
  #   affect the format qualifier.
  # Globals:
  #   O_FILE
  # Arguments:
  #   $1  Character to display
  #   $2  Number of characters to output
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local output_char=$1
  local -i num_chars=$2
  local output_line=$(
    printf "$output_char%.0s" $( (seq 1 $num_chars))
    echo
  )
  echo $output_line >>${O_FILE}
  return $SUCCESS
}

function end_table() {
  draw_separator "=" 118
}

function print_raw() {
  echo $1 >>${O_FILE}
  return $SUCCESS
}

function create_mail_header() {
  #######################################
  # Description:
  #  Create the email header.  Pass in the email addresses, subject and the output file.
  # Globals:
  #   None
  # Arguments:
  #   $1  email addres.  If more than 1, separate by commas
  #   $2  subject of the email
  #   $3  name of the file to out put to
  # Returns:
  #   $SUCCESS or $FAILURE
  # Notes:
  #######################################
  local to_addr=$1
  local subject="$2"
  local output_file=$3
  log_info "$to_addr : $subject : $output_file"
  printf "%s\n" "To: $to_addr" >>${output_file}
  printf "%s\n" "Subject: $subject" >>${output_file}
  printf "%s\n" "echo Content-Type: text/html" >>${output_file}
  printf "%s\n" "MIME-Version: 1.0" >>${output_file}
  printf "%s\n" "Content-Disposition: inline" >>${output_file}
  return $SUCCESS
}

function create_table_header() {
  local blank=" "
  fmt="| %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s |\n"
  printf "$fmt" "$blank" "$blank" "$blank" "Serial" "$blank" "$blank" "Current" "Hours" "Start/Stop" >>${O_FILE}

  printf "$fmt" "Device" "Type" "Model" "Number" "Capacity" "Temp" "Speed" "Powered On" "Count" >>${O_FILE}
  draw_separator "=" 118
  return $SUCCESS
}

function create_results_header() {
  printf "%s\n" "Status for disks found on $HOST_NAME on $(date)" >>${O_FILE}
  return $SUCCESS
}

function end_document() {
  print_raw ""
}

# Main script starts here
# The basic flow is:
#  1.  Look for which commands are available to be used to get various system, disk
#      network and other information.
#  2.  Collect the system information -- Note that this fills in the dictionary so
#      we need to be mindful of the order in which we fill in the details as some
#      decisions are made based upon info int he dictionary.
#  3.  Get information about the disks on the system
#  4.  Create a document that can be mailed and mail it desired
#

if [[ $BASH_REQ_MAJ_VER -gt $BASH_MAJ_VER ]]; then
  err "This script requires at least BASH major version $BASH_MIN_VER.  Current version is ${BASH_VERSINFO[@]}."
  die
fi

get_cmd_args "$@"

if [[ "$?" == $FAILURE ]]; then die; fi
if test -f "$O_FILE"; then
  log_info "$O_FILE exists.  Deleting."
  rm $O_FILE
fi

# NB: Need to add a function to test if sudo is required  for any of the required commands.  If so
#     print our a message and ask that it be run with sudo or root.

check_avail_commands "${ALL_CMDS[@]}"
validate_commands "${REQ_CMDS[@]}"
if [[ $? == $FAILURE ]]; then
  echo "Required commands are [$REQ_CMDS]"
  echo -n "The following are missing from the system: ["
  for key in ${!LIST_OF_COMMANDS[@]}; do
    if [ ${LIST_OF_COMMANDS[$key]} == "NO" ]; then
      echo -n "${key}  "
    fi
  done
  echo "]"
  die "Not all required commands are available."

fi

get_sys_info

# Create the document
if [[ $MAIL_FILE == "y" ]]; then create_mail_header "${EMAIL_TO}" "${MAIL_SUBJECT}" $O_FILE; fi
create_results_header
print_sys_info
create_table_header
# Go and get the disk information
get_disks
get_disk_info

# Get zpool information if available
if [ ${LIST_OF_COMMANDS[zpool]} == "YES" ]; then
  get_zpool_info LIST_OF_ZPOOLS
  echo "$(LIST_OF_ZPOOLS)"
  print_zpool_info
  check_zpool_errors
fi

# Clean up, and optionally mail the document
end_table
end_document

if [ $MAIL_FILE != "n" ]; then
  log_info "Sending the report to $EMAIL_TO"
  sendmail -t <$O_FILE
fi

log_info "Cleaning up."
log_info "Ending the disk checking script"
exit $SUCCESS
