#!/bin/bash
#   A simple script to collect some information about the disks on a Linux, FreeBSD or NetBSD server.  The data
#   is stored in a file and setup to enable mailing of the file.  I did this to brush up on my bash scrpting skills,
#   so there may be some simplier and easier ways to do some things, but I tried to varies ways to learn more
#
# Usage:
#   sh disk_check.sh command arguments
#   where:
#     -d                             turn on debug
#     -e email_address               email address to send the file to
#     -f filename                    filename to
#     -m y|n                         mail the file or not
#     -s "subject"                   subject of email
#     -o html|text                   output in either html or formatted text
#     -t long|short                  how much detail to include
#     -v                             prints out version of program
#
# Prerequisites:
#  - smartmon tools must be installed in order to use smartctl
#  - mmc-utils if host has eMMC cards
#####

## ToDo:
#    - Need to add capability to read SD cards (raspberry pi)  Info is located at
#      sys/block/mmcblk#.  Also can try the udevadm -a -c /dev/mmcblk# command
#    - Need to add ability to get information about virtual disks
#    - Clean up the get_disk functions and seperate them into getting infomration about a single disk
#      and storing infomration about a single disk.  This makes it more portable and cleaner.
#    - Try and eliminate all global values.
#    - Seperate functions, globals and constants into seperate files and source them in
#    - Check to see if the script needs to be run as sudo or root

##### Constants #####
declare -r    AUTHOR="David Hunter"
declare -r    VERSION="Version 0.5 beta"
declare -r    PROG_NAME="disk_check.sh"
declare -r    TRUE="YES"
declare -r    FALSE="NO"
declare -r -i FAILURE=1
declare -r -i SUCCESS=0
declare -r -a REQ_CMDS="awk uname hostname smartctl uptime hostname hash wc"
declare -r -a OPT_CMDS="geom lsblk dmidecode lshw blkid sysctl pr column"
declare -r -a ALL_CMDS="$REQ_CMDS $OPT_CMDS"
declare -r -i BASH_REQ_MAJ_VER=4
declare -r -i BASH_REQ_MIN_VER=0
declare -r -i BASH_MAJ_VER=${BASH_VERSINFO[0]}
declare -r -i BASH_MIN_VER=${BACH_VERSINFO[1]}

##### Global Variables #####
declare -g -l DEBUG="n"
declare -g -l MAIL_FILE="y"
declare -g -l O_FORMAT="html"
declare -g -l O_FILE="/tmp/disk_overview.html"
declare -g    EMAIL_TO="user@company.com"
declare -g -l HOST_NAME=$(hostname -f)
declare -g    MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME on $(date)"

# An assoicative array (sometimes called a dictionary) that holds system commands and if
# they are available on the system.  This will get filled in the commands are tested.
declare -A CMDS_ARRAY

# An associative array of disks.  Key is name of device and value is device type
declare -g -A LIST_OF_DISKS

# An associative array of system attributes and their values.  Note that we do prepopulate
# the array with common values we should be able to collect.  NB: That additional K/V pairs
# can be added onto (aka: multiple CPU stats).  Use a consistent naming prefix such that 
# the array can be sorted on major sections.
declare -A SYS_INFO
SYS_INFO=( [HOST_NAME]= \
           [HOST_UPTIME]= \
           [HOST_IP_NUMBER]= \
           [HOST_IP]= \
           [OS_TYPE]= \
           [OS_VER]= \
           [OS_REL]= \
           [CPU_ARCH_TYPE]= \
           [CPU_PROC_TYPE]= \
           [CPU_NUMBER]= \
           [HOST_CORE_TEMP]= \
           [BIOS_VENDOR]= \
           [BIOS_VER]= \
           [BIOS_REL_DATE]= \
           [BIOS_REV]= \
           [FIRMWARE_REV]= \
          )

# An associative array of disks found and their type.  AN example would be DISKS_FOUND[dao]=HDD
declare -A DISKS_FOUND

##### Misc functions #####

function log_info () {
  # prints out logginf information.
  # NB: Think about shifting this to use the syslog
  local file_name=$0
  local src_line=${BASH_LINENO}
  local -u severity=$1
  local mesg=$2
  declare call_stack
  call_stack=$(dump_stack 2)
  if [ $DEBUG == "y" ]; then
    printf "%(%m-%d-%Y %H:%M:%S)T %-20s %-75s %-5s %s\n" $(date +%s) "$file_name" \
                                                         "$call_stack" "$severity" "$mesg"
  fi;
  return $SUCCESS
}

function log_info_array () {
  # Given an associative array, print out its contents to log.
  # Be sure to just pass the array, aka:
  #   log_info_array name_of_array
  local key
  local -n keys=$1
  for key in ${!keys[@]}; do
    log_info "INFO" "$key : ${keys[$key]}"
  done
}

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

function dump_stack () {
# A simple call stack dumper.  The passed in parameter indicates which
# level of the stack to start at.  Normally you would start at level 1,
# which will not include the "dump_stack" function itself.  For calling from
# a debugging function, start at level 2 to not include the logging function.
  local -i i
  local -i start_level=$1
  local -a stack ret_stack
  for (( i=start_level; i<${#FUNCNAME[*]}; i++ )); do
    printf -v stack[$i] "%s" "${FUNCNAME[$i]}(${BASH_LINENO[$i-1]})."
    ((level++))
  done

  # remove the traling "."
  printf -v ret_stack "%s" "${stack[@]}"
  printf ${ret_stack%.*}
}

function die() {
  # Prints out the full call stack and then exits.
  local -i frame=0
  log_info "ERROR" "Dumping call stack.."
  while caller $frame; do
    ((frame++));
  done
  exit $FAILURE
}

function usage () {
  echo "Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y | n] [-s subject] [-o html | text]"
  echo "   where:"
  echo "     -d                             turn on debug"
  echo "     -e email_address               email address to send the file to"
  echo "     -f filename                    filename to"
  echo "     -m y|n                         mail the file or not"
  echo "     -s subject                     subject of email"
  echo "     -o html|text                   output in either html or formatted text"
  echo "     -t long|short                  how much detail to include"
  echo "     -v                             prints out version of program"
  echo " "
  echo " Prerequisites:"
  echo "  - smartmon tools must be installed in order to use smartctl"
  echo "  - mmc-utils if host has eMMC cards"
  exit $SUCCESS
}

function get_cmd_args () {
  # NB:  Since this is early and we do not know any options, we cannot
  # use functions that depend upon global options being set (aka: debug)
  # To get around for debugging, save information to local vars and
  # after all arguments have been priocessed, call the debugging functions.
  local passed_args="$*"
  local getopts

  while getopts 'vhde:f:m:s:o:' arg; do
    case $arg in
      d) DEBUG="y"
         ;;
      e) EMAIL_TO="$OPTARG"
         ;;
      f) O_FILE="$OPTARG"
         ;;
      h | \?)
        usage
        ;;
      m) MAIL_FILE="$OPTARG"
         ;;
      s) EMAIL_SUBJECT="$OPTARG"
         ;;
      o) O_FORMAT="$OPTARG"
         ;;
      v)
        printf "%s\n" "$PROG_NAME: $VERSION"
        exit $SUCCESS
        ;;
    esac
  done
  shift "$((OPTIND -1))"
  log_info "INFO" "Command line arugments passed were: $passed_args."
}

function check_file_exist() {
  # Checks for the existance of a file and returns success or failire
  local -r file="${1}"
  if [[ "${file}" = '' || ! -f "${file}" ]]; then
    return $FAILURE
  else
    return $SUCCESS
  fi
}

function check_paramcondition () {
  # Give a parameter, its warnning and error will return the param in a color code
  local param_to_check=$1
  local param_warn=$2
  local param_err=$3
}

function validate_commands () {
  # Given an array with a set of commands, if any are not available, exit the program.
  local command
  for command in $1; do
    if ! hash "$command" > /dev/null 2>&1; then
      err "Required command $command not availabe.  Please install.\n  Exiting the program."
      exit $FAILURE
    fi
  done
  return $SUCCESS
}

function check_avail_commands () {
  # Looks to see if the commands in the array passed are available on the system
  # and stores the results in the GLOBAL associative CMDS_ARRAY array
  local cmds_missing=0
  local cmd k
  declare -A commands_to_check=$1

  for cmd in $commands_to_check; do
    CMDS_ARRAY["$cmd"]=$TRUE
    if ! hash "$cmd" > /dev/null 2>&1; then
      CMDS_ARRAY["$cmd"]=$FALSE
      ((cmds_missing++))
    fi
  done

  if ((cmds_missing > 0)); then
    log_info "INFO" "$cmds_missing commands are missing or not in PATH."
  fi

  if [ $DEBUG == "y" ]; then log_info_array CMDS_ARRAY; fi;
  return $SUCCESS
}

function is_command_available () {
  # Checks the passed command and sees if it is listed as available
  # Returns SUCCESS if available or FAILURE if not found or not available
  local i
  local command_to_check_for=$1

  log_info "INFO" "Checking on status of $1 command."
  for i in ${!CMDS_ARRAY[*]}; do
    if [[ $command_to_check_for == $i ]]; then
      if [[ $TRUE == ${CMDS_ARRAY[$i]} ]]; then
        log_info "INFO" "$command_to_check_for is available ==> ${CMDS_ARRAY[$i]}."
        return $SUCCESS
      else
        log_info "INFO" "$command_to_check_for is not available ==> ${CMDS_ARRAY[$i]}."
        return $FAILURE
       fi
    fi
  done
#  return $FAILURE
}

#####  Storage Related  #####

function get_disks () {
  # Gets the disk on the system.  It tries to get the most accurate and comprehensive
  # list of disks depending upon the commands available on the machine.  It stores the
  # disks found and their type in a sorted global array, LIST_OF_DISKS.
  local -a disks
  local    device
  local    i
  local    key
  local    keys

  # Use the best command for discovery
  is_command_available geom
  if [[ $? -eq $SUCCESS ]]; then
    log_info "INFO" "Using geom command to obtain disks on the system."
    disks=$(geom disk list | grep Name | awk '{print $3}')

  else
    is_command_available lsblk;
    if [[ $? -eq $SUCCESS ]]; then
      log_info "INFO" "Using the lsblk command to obtain disks on the system."
      disks=$(lsblk -dp | grep -o '^/dev[^ ]*'  | sed 's/\/dev\///')

    else
     log_info "ERROR" "Unable to find a command to get disks.  Aborting."
     err "Unable to find a command to get disks. Aborting."
     exit $FAILURE
    fi
  fi

  # Remove carriage returns and sort the array and then for each
  # disk, get its type and store inthe global array of disks
  disks=$(sort <<< "${disks[*]}")
  disks=$(echo "$disks" | tr '\n' ' ')
  log_info "INFO" "Array of disks found: $disks"

  for device in $disks; do
    LIST_OF_DISKS[$device]=$(get_disk_type "$device")
  done

  log_info "INFO" "The number of disks in the array are: ${#LIST_OF_DISKS[@]}"
  # Dump out the LIST_OF_DISK Dictionary but first sort by key name
  # to make reading a bit easier.
  if [ $DEBUG == "y" ]; then
    keys=`echo ${!LIST_OF_DISKS[@]} | tr ' ' '\012' | sort | tr '\012' ' '`
    log_info "INFO" "Dumping the LIST_OF_DISKS Dictionary..."
    log_info_array LIST_OF_DISKS
  fi
}

function get_disk_type () {
  # Given a disk device, printout the type of disk
  local disk=$1
  local dev_type
  local results=$(smartctl -a /dev/$disk)
  local ssd=$(grep 'Solid State Device' <<< $results)
  local usb=$(grep 'USB bridge' <<< $results)
  local offline=$(grep 'INQUIRY failed' <<< $results)
  local vmware=$(grep 'VMware' <<< $results)
  local hdd=$(grep 'rpm' <<< $results)

  if [[ -n "${ssd/[ ]*\n}" ]]; then
    dev_type="SSD"
  elif [[ -n "${usb/[ ]*\n/}" ]]; then
    dev_type="USB"
  elif [[ -n "${offline/[ ]*\n}" ]]; then
    dev_type="O/L"
  elif [[ -n "${vmware/[ ]*\n}" ]]; then
    dev_type="VMW"
  elif [[ -n "${hdd/[ ]*\n}" ]]; then
    dev_type="HDD"
  else
    dev_type="UKN"
  fi
  printf "%s\n" $dev_type
  return $SUCCESS
}

function get_disk_info () {
  # Cycle thrrough the disks and collect data dependent upon what type
  # ToDo: Transform into multiple functions:
  #         - print_disk_info -- Given a disk assoc array and links to detail assoc arrays, print out the info
  local i
  local  key
  local -a keys

  # We have the list of disk and disk types in LIST_OF_DISK associative array.  Since we want to do this in a
  # sorted fashion, create an index array of the indexes, sort it and use it to itterate through the global array
  keys=`echo ${!LIST_OF_DISKS[@]} | tr ' ' '\012' | sort | tr '\012' ' '`
  for key in $keys; do
    # Reset all the variables to blank to prevent looping for blank results.
    local max_speed="    Gb/s"
    local cur_speed="    Gb/s"
    local ser_num="-"
    local model="-"
    local dev_type="UKN"
    local capacity="     xB"
    local pwr_local on_hrs="-"
    local start_stop_ct="-"
    local total_seeks="-"
    local spin_errors="-"
    local cmd_errors="-"
    local test_results="-"
    local bad_sectors="-"
    local temp="-"

    full_results=$(smartctl -a /dev/$key)
    log_info "INFO" "Examing device $key which is ${LIST_OF_DISKS[$key]} device."

    #  For each of the device types, collect those common SMART values that could indicate an issue
    #  You can find more details at https://en.wikipedia.org/wiki/S.M.A.R.T.
    case ${LIST_OF_DISKS[$key]} in
        HDD | SSD)
          ser_num=$(grep        'Serial Number'         <<< $full_results | awk '/Serial Number/         {print $3}')
          model=$(grep          'Device Model'          <<< $full_results | awk '/Device Model/          {print $3 $4}')
          capacity=$(grep       'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5, $6}' | sed -e 's/^.//' -e 's/.$//')
          max_speed=$(grep      'SATA Version'          <<< $full_results | awk '/SATA Version/          {print $6, $7}')
          cur_speed=$(grep      'SATA Version'          <<< $full_results | awk '/SATA Version/          {print $9, substr($10, 1, length($10)-1)}')
          pwr_on_hrs=$(grep     'Power_On_Hours'        <<< $full_results | awk '/Power_On_Hours/        {print $10}')
          start_stop_ct=$(grep  'Start_Stop_Count'      <<< $full_results | awk '/Start_Stop_Count/      {print $10}')
          total_seeks=$(grep    'End-to-End'            <<< $full_results | awk '/End-to-End/            {print $10}')
          spin_errors=$(grep    'Spin_Retry_Count'      <<< $full_results | awk '/Spin_Retry_Count/      {print $10}')
          cmd_errors=$(grep     'Command_Timeout'       <<< $full_results | awk '/Command_Timeout/       {print $10}')
          test_results=$(grep   'test result'           <<< $full_results | awk '/test result/           {print $6}')
          bad_sectors=$(grep    'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
          temp=$(grep           'Temperature_Celsius'   <<< $full_results | awk '/Temperature_Celsius/   {print $10}')
          ;;

        SSD)
          ;;

        VMW)
          ;;

        USB)
          full_results=$(smartctl -a -d scsi /dev/$i)
          model=$(grep 'Product' <<< $full_results | awk '/Product/ {print $2, $3, $4}')
          capacity=$(grep 'User Capacity' <<< $full_results | awk '/User Capacity/ {print $5, $6}' | sed -e 's/^.//' -e 's/.$//')
          ser_num=$(grep 'Vendor:' <<< $full_results | awk '/Vendor:/ {print $3}')
          start_stop_ctq=$(grep 'Power_Cycle_Count' <<< $full_results | awk '/Power_Cycle_Count/ {print $10}')
          test_results="-"
          bad_sectors="-"
          temp="-"
          ;;

        OFFLINE)
          log_info "INFO" "Disk is offline."
          ;;

        UKN)
          log_info "INFO" "Unknown disk type"
          ;;
      esac

      case $O_FORMAT in
        html)
          print_row "$i" "$dev_type" "$ser_num" "$model" "$capacity" "$max_speed" "$cur_speed" \
                    "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" \
                    "$spin_errors" "$cmd_errors" "$test_results" "$bad_sectors" "$temp"
          ;;

      text)
          fmt="| %-6.6s | %-7.7s | %-20.20s | %-20.20s | %10.10s | %-8.8s | %-8.8s | %10.10s | %10.10s | %10.10s | %10.10s | %10.10s | %10.10s | %10.10s | %5.5s |\n"
          printf "$fmt" "$key" "${LIST_OF_DISKS[$key]}" "$ser_num" "$model" "$capacity" "$max_speed" \
                        "$cur_speed" "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" "$spin_errors" \
                        "$cmd_errors" "$test_results" "$bad_sectors" "$temp" \
                        >> ${O_FILE}
          ;;
      esac
  done
  return $SUCCESS
}

#####  System related functions #####

function get_cpu_info () {
  # Retrieves varous infomation about the CPU and stores it in the
  # SYS_INFO global array
  SYS_INFO[CPU_ARCH_TYPE]=$(uname -m)
  SYS_INFO[CPU_PROC_TYPE]=$(uname -p)

  if [[ -z ${SYS_INFO[OS_TYPE]} ]]; then
    log_info "INFO" "OS_TYPE not defined.  Calling get_os_info"
    get_os_info
  fi

  log_info "INFO" "Checking for cpu count under ${SYS_INFO[OS_TYPE]}"
  case ${SYS_INFO[OS_TYPE]} in
    FreeBSD)
      SYS_INFO[CPU_NUMBER]=$(sysctl -n hw.ncpu)
      SYS_INFO[CPU_MODEL]=$(sysctl -n hw.model)
      SYS_INFO[HOST_PHYS_MEM]=$(sysctl -n hw.physmem)
      ;;

    Linux)
      SYSINFO[CPU_NUMBER]=$(grep -c '^processor' /proc/cpuinfo)
      SYSINFO[CPU_MODEL]=$(grep 'model name' /proc/cpuinfo)
      SYS_INFO[HOST_PHYS_MEM]=$(grep MemTotal /proc/meminfo)
      ;;
  esac

  log_info "INFO" "Number of cpus found is: ${SYS_INFO[CPU_NUMBER]}"
  return $SUCCESS
}

function get_hw_info () {
  # Retrieve various hardware related information and store in the KV array

  return $SUCCESS
}

get_bios_info () {
  # Retrieve information about the bios.  the dmidecode command is requried.

  return $SUCCESS
}

function get_temps () {
  # Get temperatures of various elements (board, cpu, etc.) and add to SYS_INFO array  
  local    i
  local -i num_cpu_temps=0
  local    cpu_temps

  case ${SYS_INFO[OS_TYPE]} in
    FreeBSD)
#      num_cpu_temps=$(sysctl -a | grep temperature | awk '{print $2}' | wc -l)
      cpu_temps=($(sysctl -a | grep temperature | awk '{print $2}'))

      # When called it will return an array of temps depending upon the ncpus
      # Store all the temps in SYS_INFO[CPU_TEMP] and then add individual temps to dictionary
      if [[ ${#cpu_temps[@]} -gt 0 ]]; then
        SYS_INFO[CPU_TEMP]="${cpu_temps[@]}"
        for i in "${cpu_temps[@]}"; do
          SYS_INFO[CPU_TEMP_$num_cpu_temps]=${cpu_temps[num_cpu_temps]}
          log_info "INFO" "CPU number [$num_ip_addrs] temperature is: ${SYS_INFO[CPU_TEMP_$num_cpu_temps]}."
          ((num_cpu_temps++))
        done
      else
        SYS_INFO[CPU_TEMP]="0.0"
        log_info "INFO" "CPU temperature not found."
      fi
      ;;

    Linux)
      SYS_INFO[HOST_CORE_TEMP]=0
      CPU_TEMP=0
      ;;
    # For raspberry pi use /opt/vc/bin/vcgencmd measure_temp
  esac
  return $SUCCESS
}

function get_host_info () {
  # Retrieves infomration about the system and stores it into the SYS_INFO dictionary
  local    ip_addrs
  local -i num_ip_addrs=0
  local    i

  SYS_INFO[HOST_NAME]=$(hostname -f | tr '[:lower:]' '[:upper:]')
  # NB: Should fix to extract just hours and days up vs the entire string. 
  #  SYS_INFO[HOST_UPTIME]=$(uptime | awk '{ print $3, $4, $5 }' | sed 's/,//g' | sed 's/\r//g')
  SYS_INFO[HOST_UPTIME]=$(uptime)
  ip_addrs=($(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'))
  log_info "INFO" "Number of host ip addresses found is: ${#ip_addrs[@]}."
  SYS_INFO[HOST_IP_NUMBER]=${#ip_addrs[@]}

  # A system may have more than 1 ip address or interface.  Count the number and create an array with the ips.
  # We store all the ips found in HOST_IP and if more than 1, add unique SYS_INFO[HOST_IP_x] for each.
  if [[ ${#ip_addrs[@]} -gt 0 ]]; then
    SYS_INFO[HOST_IP]=${ip_addrs[@]}
    for i in "${ip_addrs[@]}"; do
      SYS_INFO[HOST_IP_$num_ip_addrs]=${ip_addrs[num_ip_addrs]}
      log_info "INFO" "IP address number [$num_ip_addrs] found is: ${SYS_INFO[HOST_IP_$num_ip_addrs]}."
      ((num_ip_addrs++))
    done
  else
    SYS_INFO[HOST_IP]="0.0.0.0"
    log_info "INFO" "IP address not found, setting to ${SYS_INFO[HOST_IP]}."
  fi
  return $SUCCESS
}

function get_os_info () {
  # Stores  info about the operating system in the SYS_INFO dictionary
  SYS_INFO[OS_TYPE]=$(uname -s)
  SYS_INFO[OS_VER]=$(uname -o)
  SYS_INFO[OS_REL]=$(uname -r)
  return $SUCCESS
}

function get_sys_info () {
  # Collects various system information  and stores it in the global array.
  # If KV pair not found, it will assume its a new one andpopo it onto
  # the array.  For each value, we want to utilize a function to fill in the
  # key-pair to allow for portability.  Ensure we collect any variables that
  # are used to make decisions early (OS_TYPE, ARCH_TYPE, PROC_TYPE).
  local    key
  local -a keys

  get_hw_info
  get_os_info
  get_bios_info
  get_cpu_info
  get_host_info
  get_temps

  # Dump out the SYS_INFO Dictionary but first sort by key name
  # to make reading a bit easier.
  if [ $DEBUG == "y" ]; then
    local keys=`echo ${!SYS_INFO[@]} | tr ' ' '\012' | sort | tr '\012' ' '`
    log_info "INFO" "Dumping the SYS_INFO Dictionary..."
    log_info_array SYS_INFO
  fi
  return $SUCCESS
}

function print_sys_info () {
  # Prints out simple system information.  This simply dumps the 
  # keys and values in the SYS_INFO array
  local    key
  local -a keys

  local keys=`echo ${!SYS_INFO[@]} | tr ' ' '\012' | sort | tr '\012' ' '`
  case $O_FORMAT in
    html)
      print_raw "<p>"
      for key in $keys; do
        print_raw "<b>$key:          </b> ${SYS_INFO[$key]}<br>"
      done
      print_raw "</p>"
      ;;

    text)
      local fmt="%-60.60s%-60.60s%60.60s\n"
      printf "%s\n" "============================" >> ${O_FILE}
      printf "%s\n" "    System Information" >> $O_FILE
      printf "%s\n" "============================" >> ${O_FILE}
      for key in $keys; do
        printf "%-25s %-25s\n" "$key:" "${SYS_INFO[$key]}" 
      done | column >> ${O_FILE}
      draw_separator
  esac
  return $SUCCESS
}

##### Some simple text based Output Functions #####

function draw_separator () {
  local output_char="="
  local -i num_chars=200
  local output_line=$(printf "$output_char%.0s" `(seq 1 $num_chars)`; echo)
  echo $output_line  >> ${O_FILE}
}

function draw_row () {
  local i
  for i in "$@"; do
    printf "%20.20s" "$i" >> ${O_FILE}
  done
  printf "\n" >> ${O_FILE}
  draw_separator
  return $SUCCESS
}

##### Some simple HTML Output Functions #####

function start_table () {
  echo "<table id="storage" border=2 cellpadding=4>" >> ${O_FILE}
}

function end_table () {
  case $O_FORMAT in
    html)
     print_raw "</table>"
     ;;
    text)
     draw_separator
     ;;
  esac
}

function print_td () {
  echo "<td>$1</td>" >> ${O_FILE};
  return $SUCCESS;
}

function print_raw () {
  echo $1 >> ${O_FILE};
  return $SUCCESS
}

function start_row () {
  echo "<tr>" >> ${O_FILE};
  return $SUCCESS
}

function end_row () {
  echo "</tr>" >> ${O_FILE};
  return $SUCCESS
}

function print_row() {
  local i
  start_row
  for i in "$@"; do
    print_td "$i"
  done
  end_row
  return $SUCCESS
}

##### Document functions #####

function create_mail_header () {
#  Create the email header.  Pass in the email addresses, subject and the output file.
  local to_addr=$1
  local subject=$2
  local output_file=$3
  (
   echo To: $EMAIL_TO
   echo Subject: $MAIL_SUBJECT
   echo Content-Type: text/html
   echo MIME-Version: 1.0
   echo Content-Disposition: inline
  ) > ${O_FILE}
  return $SUCCESS
}

function create_table_header () {
 case $O_FORMAT in
    html)
      print_raw "<table id="storage" border=2 cellpadding=4>"
      print_row "Device" "Type" "Serial #" "Model" "Capacity" "Speed" "Current Speed" "Hours Powered On" "Start/Stop Count" \
                "End to End Errors" "Spin Retries" "Command Timeouts" "Last Test" "Reallocated Sectors" "Temp"
      ;;

    text)
      fmt="| %-6.6s | %-7.7s | %-20.20s | %-20.20s | %-10.10s | %-8.8s | %-8.8s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-10.10s | %-5.5s |\n"
      printf "$fmt" " " " " " " " " " " "Max" "Current" "Hours" "Start/Stop" \
                "End to End" "Spin" "Command" "Last Test" "Realloc" "Temp" >> ${O_FILE}
      printf "$fmt" "Device" "Type" "Serial #" "Model" "Capacity" "Speed" "Speed" "Powered On" \
             "Count" "Errors" "Retries" "Timeouts" "Results" "Sectors" "Temp" >> ${O_FILE}
      draw_separator
      ;;
  esac
  return $SUCCESS
}

function create_results_header () {
  case $O_FORMAT in
    html) 
      print_raw "<!DOCTYPE html>"
      print_raw "<html>"
      print_raw "<head>"
      print_raw "p {font-size: 75; color: back; font: monospace}"
      print_raw "h1 {font-size: 75pct; color: blue; font: monospace}"
      print_raw "</head>"
      print_raw "<body>"
      print_raw "<h1>Status for Disks Found on $HOST_NAME on $(date '+%Y-%m-%d')</h1>"
      ;;

    text)
      printf "%s\n" "<html><body><pre style='font: monospace'>" >> ${O_FILE}
      printf "$s\n" "Status for disks found on $HOST_NAME on $(date '+$Y-%m-$d')" >> ${O_FILE}
      ;;
  esac
  return $SUCCESS
}

function end_document () {
  case $O_FORMAT in
    html)
      print_raw "</body></html>"
      ;;
    text)
      print_raw "</pre></body></html>"
      ;;
  esac
}

##### Main script starts here #####
####
#
# The basic flow is:
#  1.  Look for which commands are available to be used to get various system, disk
#      network and other information.
#  2.  Collect the system information -- Note that this fills in the dictionary so
#      we need to be mindful of the order in which we fill in the details as some 
#      decisions are made based upon info int he dictionary.
#  3.  Get information about the disks on the system
#  4.  Create a document that can be mailed and mail it desired
#
####

if [[ $BASH_REQ_VER -gt $BASH_MAJ_VER ]]; then
  err "This script requires at least BASH major version $BASH_MIN_VER.  Current version is ${BASH_VERSINFO[@]}."
  die
fi

get_cmd_args "$@"

if  [[ "$?" == $FAILURE ]]; then
  die
fi

if test -f "$O_FILE"; then
  log_info "INFO" "$O_FILE exists.  Deleting."
  rm $O_FILE
fi

# NB: Need to add a function to test if sudo is required  for any of the required commands.  If so
#     print our a message and ask that it be run with sudo or root.

check_avail_commands "${ALL_CMDS[@]}"
validate_commands "${REQ_CMDS[@]}"
get_sys_info

# Create the document
create_mail_header $EMAIL_TO $MAIL_SUBJECT $O_FILE
create_results_header
print_sys_info
create_table_header

# Go and get the disk information
get_disks
get_disk_info

# Clean up, and optionally mail the document
end_table
end_document

if [ $MAIL_FILE != "n" ]; then
  log_info "INFO" "Sending the report to $EMAIL_TO"
  sendmail -t < $O_FILE
fi

log_info "INFO" "Cleaning up."
log_info "INFO" "Ending the disk checking script"
exit $SUCCESS

    # The following are the meaning of the smartcrl data items.
    #  Reallocated Sectors Count            Count of reallocated sectors. The raw value represents a
    #                                       count of the bad sectors that have been found and remapped.
    #                                       Thus, the higher the attribute value, the more sectors the
    #                                       drive has had to reallocate. This value is primarily used as
    #                                       a metric of the life expectancy of the drive; a drive which
    #                                       has had any reallocations at all is significantly more likely
    #                                       to fail in the immediate months
    #
    #  Spin Retry Count                     Count of retry of spin start attempts. This attribute stores
    #                                       a total count of the spin start attempts to reach the fully
    #                                       operational speed (under the condition that the first attempt
    #                                       was unsuccessful). An increase of this attribute value is a
    #                                       sign of problems in the hard disk mechanical subsystem.
    #
    #  End-to-End error / IOEDC             This attribute is a part of Hewlett-Packard's SMART IV technology,
    #                                       as well as part of other vendors' IO Error Detection and
    #                                       Correction schemas, and it contains a count of parity errors which
    #                                       occur in the data path to the media via the drive's cache RAM.
    #
    #  Reported Uncorrectable Errors        The count of errors that could not be recovered using hardware ECC.
    #
    #  Command Timeout                      The count of aborted operations due to HDD timeout. Normally this
    #                                       attribute value should be equal to zero
    #
    #  Reallocation Event Count             Count of remap operations. The raw value of this attribute shows
    #                                       the total count of attempts to transfer data from reallocated
    #                                       sectors to a spare area. Both successful and unsuccessful
    #                                       attempts are counted
