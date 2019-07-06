#!/bin/bash
# ---
# Description:
#   A simple script to collect some information about the disks on the freenas server.  The data
#   is stored in a file and setup to enable mailing of the file.
# Usage:
#   sh disk_check.sh command arguments
#   where:
#     -d                             turn on debug
#     -e email_address               email address to send the file to
#     -f filename                    filename to 
#     -m y|n                         mail the file or not
#     -s "subject"                   subject of email
#     -o html|text                   output in either html or formatted text
#--- 

##### Check for min versions  #####
BASH_MIN_VER="4"
BASH_CUR_VER=$(bash --version | grep 'GNU bash' | awk '{print substr($4,1,1)}')

if [[ $BASH_MIN_VER != $BASH_CUR_VER ]]; then
  printf "%(%m-%d-%Y %H:%M:%S)T\t%s\t%s\n" $(date +%s) $0 "ERROR ${FUNCNAME[0]} This script requires at least BASH $BASH_MIN_VER."
  exit 1
fi

#####  Global Variables and Constants #####
TRUE="YES"
FALSE="NO"
FAILURE=1
SUCCESS=0

DEBUG="n"
MAIL_FILE="y"
O_FORMAT="html"
O_FILE="/tmp/disk_overview.html"
EMAIL_TO="user@company.com"
HOST_NAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME on $(date)"

DISKS=""
LIST_OF_DISKS=""

UPTIME=$(uptime | awk '{ print $3, $4, $5 }' | sed 's/,//g')
ARCH_TYPE=$(uname -m)
PROC_TYPE=$(uname -p)
OS_TYPE=$(uname -s)
OS_VER=$(uname -o)
OS_REL=$(uname -r)

declare -A CMDS
REQ_CMDS="awk uname hostname smartctl uptime"
OPT_CMDS="geom lsblk dmidecode lshw blkid sysctl"
ALL_CMDS="$REQ_CMDS $OPT_CMDS"

##### Functions #####

function check_avail_commands () {
  local cmds_missing=0
  local i=''

  for i in $ALL_CMDS; do
    CMDS["$i"]=$TRUE
    if ! hash "$i" > /dev/null 2>&1; then
      CMDS["$i"]=$FALSE
      ((cmds_missing++))
    fi
  done

  log_info "${FUNCNAME[0]}" "INFO" "Number of commands to check is: ${#CMDS[*]}"
  if ((cmds_missing > 0)); then
    log_info "${FUNCNAME[0]}" "INFO" "$cmds_missing commands are missing or not in PATH."
  else
    log_info "${FUNCNAME[0]}" "INFO" "All commands are found on the system."
  fi

  for i in ${!CMDS[*]}; do
     log_info "${FUNCNAME[0]}" "INFO" " $i : ${CMDS[$i]}"
  done
  return $SUCCESS
}

function command_available () {
  local i=''
  log_info "${FUNCNAME[0]}" "INFO" "Number of commands to check: ${#CMDS[*]}."
  log_info "${FUNCNAME[0]}" "INFO" "Checking on status of $1 command."

  for i in ${!CMDS[*]}; do
    if [[ $1 == $i ]]; then
      log_info "${FUNCNAME[0]}" "INFO" "Commands $1 found and is available: ${CMDS[$i]}."
      return 0
    fi
  done
  return $SUCCESS
}

function get_disks () {
  log_info "${FUNCNAME[0]}" "INFO" "Generating a list of all disks on the system."
  command_available geom
  if [[ $? -eq 0 ]]; then
    log_info "${FUNCNAME[0]}" "INFO" "geom command available."
    DISKS=$(geom disk list | grep Name | awk '{print $3}')

  else
    command_avail lsblk;
    if [[ $? -eq 0 ]]; then
      log_info "${FUNCNAME[0]}" "INFO" "lsblk command available."
      
    else
     log_info "${FUNCNAME[0]}" "ERROR" "No disks found.  Aborting."
     exit $FAILURE
    fi
  fi

  LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")
  if [[ -z $LIST_OF_DISKS ]]; then
    log_info "${FUNCNAME[0]}" "ERROR" "No disks found.  Aborting."
    exit $FAILURE
  fi
}

function print_sys_info () {
  log_info "${FUNCNAME[0]}" "INFO" "-- System Information ------------"
  log_info "${FUNCNAME[0]}" "INFO" "================================"
  log_info "${FUNCNAME[0]}" "INFO" "Host Name:      $HOSTNAME"
  log_info "${FUNCNAME[0]}" "INFO" "System Uptime:  $UPTIME"
  log_info "${FUNCNAME[0]}" "INFO" "Arch Type:      $ARCH_TYPE"
  log_info "${FUNCNAME[0]}" "INFO" "Procesor Type:  $PROC_TYPE"
  log_info "${FUNCNAME[0]}" "INFO" "OS Version:     $OS_VER"
  log_info "${FUNCNAME[0]}" "INFO" "OS Release:     $OS_REL"  
  log_info "${FUNCNAME[0]}" "INFO" "================================"
  return $SUCCESS
}

function log_info () {
# A simple logging function
# NB: Should move to logger to be consistent with syslog 
  if [ $DEBUG == "y" ]; then 
    printf "%(%m-%d-%Y %H:%M:%S)T\t%s\t%s\t%s\t%s\n" $(date +%s) "$0 ${FUNCNAME[0]} $1 $2 $3"; fi; 
  return $SUCCESS
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
  expected_inputs=15
  if [ $expected_inputs -ne $# ]; then
    printf "%s\n" "ERROR -- ${FUNCNAME} -- Incorrect number of parameters passed."
    printf "%s\n%s" "Number of passed parameter was: $#."  "List of parameters: "
    for i in "$@"; do
      printf "%s" "$i..."
    done
    printf "\n%s\n" "Exiting."
    return $FAILURE
  fi
  start_row
  for i in "$@"; do
    print_td "$i"
  done
  end_row
  return $SUCCESS
}

#### Main script starts here

#  Parse the command line arguments
while getopts 'de:f:m:s:o:' arg; do
  case $arg in
    d)      DEBUG="y"           ;;
    e)      EMAIL_TO="$OPTARG"  ;;
    f)      O_FILE="$OPTARG"    ;;
    m)      MAIL_FILE="$OPTARG" ;;
    s)      EMAIL_SUBJECT="$OPTARG" ;;
    o)      O_FORMAT="$OPTARG"  ;;
    ? | h)  printf "\n%s\n\n" "Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y/n] [-s subject] "
            exit 1             ;;
    :)      printf "\n\t %s %s %s" "Illegal option: " $OPTARG "requires an argument"
            exit 1             ;;
  esac
done
shift "$((OPTIND -1))"

log_info "${FUNCNAME[0]}" "INFO" "Starting the disk check script."
if test -f "$O_FILE"; then
  log_info "${FUNCNAME[0]}" "INFO" "$O_FILE exists.  Deleting."
  rm $O_FILE
fi

if [ $DEBUG == "y" ]; then print_sys_info; fi;

check_avail_commands

#  Create the email header
(
echo To: $EMAIL_TO
echo Subject: $MAIL_SUBJECT
echo Content-Type: text/html
echo MIME-Version: 1.0
) > ${O_FILE}

#  Create the HTML PAGE portion
print_raw "<!DOCTYPE html>"
print_raw "<html>"
print_raw "<head>"
print_raw "<style>"
print_raw "body {font-family: verdana, Arial, Helvetica, sans-serif; color: black;}"
print_raw "#storage { font-family: Trebuchet MS, Arial, Helvetica, sans-serif; border-collapse: collapse; width: 100%;}"
print_raw "#storage td, #storage th{ border: 1px solid #ddd; padding: 8px; text-align: right; }"
print_raw "#storage tr:nth-child(even){background-color: $f2f2f2;}"
print_raw "#storage tr:hover {background-color: #ddd;}"
print_raw "#storage th {padding-top:12px; padding-bottom: 12px; text-align: right; background-color: #4CAF50; color: white; }"
print_raw "</style>"
print_raw "</head>"
print_raw "<body>"


#  Create an HTML Table of the results.  This tends to read better on mail readers and phones than
#  just outputing formatted text. 

print_raw "<h1>Status for Disks Found on $HOST_NAME on $(date "+%Y-%m-%d")</h1>"
print_raw "<table id="storage" border=2 cellpadding=4>"
print_row "Device" "Type" "Serial #" "Model" "Capacity" "Speed" "Current Speed" "Hours Powered On" "Start/Stop Count" \
          "End to End Errors" "Spin Retries" "Command Timeouts" "Last Test" "Reallocated Sectors" "Temp"

#  Cycle thrrough the disks and collect data dependent upon what type
get_disks

log_info "${FUNCNAME[0]}" "INFO" "Iterrating through disks."
for i in $LIST_OF_DISKS 
  do
    #  Reset all the variables to blank
    max_speed="NA"
    cur_speed="NA"
    ser_num="NA"
    model="NA"
    dev_type="NA"
    capacity="NA"
    pwr_on_hrs="NA"
    start_stop_ct="NA"
    total_seeks="NA"
    spin_errors="NA"
    cmd_errors="NA"
    test_results="NA"
    bad_sectors="NA"
    temp="NA"

    #  Just do the smartctl call once if possible
    full_results=$(smartctl -a /dev/$i)
    ssd_dev=$(grep 'Solid State Device' <<< $full_results)
    usb_dev=$(grep 'USB bridge' <<< $full_results)
    offline_dev=$(grep 'INQUIRY failed' <<< $full_results)

    #  Try to classify the device type
    if [[ -n "${ssd_dev/[ ]*\n}" ]]; then
      dev_type="SSD"
    elif [[ -n "${usb_dev/[ ]*\n/}" ]]; then
      dev_type="USB"      
    elif [[ -n "${offline_dev/ [ ]*\n}" ]]; then
      dev_type="OFFLINE"
    else
      dev_type="HDD"
    fi
    log_info "${FUNCNAME[0]}" "INFO" "Examing device $i which is $dev_type device."

    #  For each of the device types, collect those common SMART values that could indicate an issue 
    #  You can find more details at https://en.wikipedia.org/wiki/S.M.A.R.T.
    case $dev_type in
      HDD | SSD)
        ser_num=$(grep        'Serial Number'         <<< $full_results | awk '/Serial Number/         {print $3}')
        model=$(grep          'Device Model'          <<< $full_results | awk '/Device Model/          {print $3 $4}')
        capacity=$(grep       'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5, $6}')
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

      USB)
        full_results=$(smartctl -a -d scsi /dev/$i)
        model=$(grep 'Product'                        <<< $full_results | awk '/Product/               {print $2, $3, $4}')
        capacity=$(grep       'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5, $6}')
        ser_num=$(grep        'Vendor:'               <<< $full_results | awk '/Vendor:/               {print $3}')
        start_stop_ctq=$(grep     'Power_Cycle_Count'     <<< $full_results | awk '/Power_Cycle_Count/     {print $10}')
        test_results="N/A"
        bad_sectors="N/A"
        temp="N/A"
        ;;

      OFFLINE)
        log_info "${FUNCNAME[0]}" "INFO" "Disk is offline."
        ;;

      *)
        log_info "${FUNCNAME[0]}" "INFO" "Unknown disk type"
        ;;
    esac

    #  Print out the table row
    print_row "$i" "$dev_type" "$ser_num" "$model" "$capacity" "$max_speed" "$cur_speed" \
              "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" \
              "$spin_errors" "$cmd_errors" "$test_results" "$bad_sectors" "$temp"

 done


print_raw "</table>"

#  End the HTML document properly
print_raw "</body>"
print_raw "</html>"

#  Send the file if required. 

if [ $MAIL_FILE != "n" ]
then
  log_info "${FUNCNAME[0]}" "INFO" "Sending the report to $EMAIL_TO"
  sendmail -t < $O_FILE
else
  log_info "${FUNCNAME[0]}" "INFO" "Not sending file"
fi

#  Clean up 
log_info "${FUNCNAME[0]}" "INFO" "Cleaning up."

if [ $DEBUG = "n" ]
then
  log_info "${FUNCNAME[0]}" "INFO" "Deleting $O_FILE."
  rm $O_FILE
fi

log_info "${FUNCNAME[0]}" "INFO" "Ending the disk checking script"

return $SUCCESS



    #  Reallocated Sectors Count            Count of reallocated sectors. The raw value represents a 
    #                                          count of the bad sectors that have been found and remapped. 
    #                                          Thus, the higher the attribute value, the more sectors the 
    #                                          drive has had to reallocate. This value is primarily used as 
    #                                          a metric of the life expectancy of the drive; a drive which 
    #                                          has had any reallocations at all is significantly more likely 
    #                                          to fail in the immediate months
    #
    #  Spin Retry Count                     Count of retry of spin start attempts. This attribute stores
    #                                          a total count of the spin start attempts to reach the fully 
    #                                          operational speed (under the condition that the first attempt 
    #                                          was unsuccessful). An increase of this attribute value is a 
    #                                          sign of problems in the hard disk mechanical subsystem.
    #
    #  End-to-End error / IOEDC             This attribute is a part of Hewlett-Packard's SMART IV technology,
    #                                          as well as part of other vendors' IO Error Detection and 
    #                                          Correction schemas, and it contains a count of parity errors which
    #                                          occur in the data path to the media via the drive's cache RAM.
    #
    #  Reported Uncorrectable Errors        The count of errors that could not be recovered using hardware ECC.
    #
    #  Command Timeout                      The count of aborted operations due to HDD timeout. Normally this 
    #                                          attribute value should be equal to zero
    #
    #  Reallocation Event Count             Count of remap operations. The raw value of this attribute shows 
    #                                          the total count of attempts to transfer data from reallocated 
    #                                          sectors to a spare area. Both successful and unsuccessful attempts are counted
