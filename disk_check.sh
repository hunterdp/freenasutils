#!/bin/bash
#   A simple script to collect some information about the disks on a Linux, FreeBSD or NetBSD server.  The data
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
#####

##### Constants #####
declare -r TRUE="YES"
declare -r FALSE="NO"
declare -r FAILURE=1
declare -r SUCCESS=0
declare -r REQ_CMDS="awk uname hostname smartctl uptime hostname hash"
declare -r OPT_CMDS="geom lsblk dmidecode lshw blkid sysctl pr column"
declare -r ALL_CMDS="$REQ_CMDS $OPT_CMDS"
declare -r BASH_MIN_VER="4"
declare -r BASH_CUR_VER=$(bash --version | grep 'GNU bash' | awk '{print substr($4,1,1)}')

##### Global Variables #####
declare -A CMDS_ARRAY
declare -l DEBUG="n"
declare -l MAIL_FILE="y"
declare -l O_FORMAT="html"
declare -l O_FILE="/tmp/disk_overview.html"
declare EMAIL_TO="user@company.com"
declare HOST_NAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
declare MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME on $(date)"
declare DISKS=""
declare LIST_OF_DISKS=""
declare UPTIME
declare ARCH_TYPE
declare PROC_TYPE
declare OS_TYPE
declare OS_VER
declare OS_REL


##### Functions #####

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

#---------------------
### File functions ###
#---------------------

function check_file_exist()
{
  local -r file="${1}"
  if [[ "${file}" = '' || ! -f "${file}" ]]; then
    return $FAILURE
  else
    return $SUCCESS
  fi
}

#------------------------
### Command functions ### 
#------------------------
function check_avail_commands () {
  # Looks to see if the commands in the array passed are available on the system
  # and stores the results in the GLOBAL associative CMDS_ARRAY array

  local cmds_missing=0
  local i=''
  declare -A commands_to_check=$1

  for i in $commands_to_check; do
    CMDS_ARRAY["$i"]=$TRUE
    if ! hash "$i" > /dev/null 2>&1; then
      CMDS_ARRAY["$i"]=$FALSE
      ((cmds_missing++))
    fi
  done

  log_info "${FUNCNAME[0]}" "INFO" "Checking ${#CMDS_ARRAY[*]} commands."
  if ((cmds_missing > 0)); then
    log_info "${FUNCNAME[0]}" "INFO" "$cmds_missing commands are missing or not in PATH."
  else
    log_info "${FUNCNAME[0]}" "INFO" "All commands are found on the system."
  fi

  if [ $DEBUG == "y" ]; then
    for i in ${!CMDS_ARRAY[*]}; do
       log_info "${FUNCNAME[0]}" "INFO" " $i : ${CMDS_ARRAY[$i]}"
    done
  fi
  return $SUCCESS
}

function is_command_available () {
  # Checks the passed command and sees if it is listed as available
  # Returns SUCCESS if available or FAILURE if not found or not available

  local command_element=""
  local command_to_check_for=$1

  log_info "${FUNCNAME[0]}" "INFO" "Checking on status of $1 command."
  for command_element in ${!CMDS_ARRAY[*]}; do
    if [[ $command_to_check_for == $command_element ]]; then
      log_info "${FUNCNAME[0]}" "INFO" "Commands $command_to_check_for found."

      if [[ $TRUE == ${CMDS_ARRAY[$command_element]} ]]; then
        log_info "${FUNCNAME[0]}" "INFO" "$command_to_check_for is available. ${CMDS_ARRAY[$command_element]}."
        return $SUCCESS
      else
        log_info "${FUNCNAME[0]}" "INFO" "$command_to_check_for is not available. ${CMDS_ARRAY[$command_element]}."
        return $FAILURE
       fi
    fi
  done

  log_info "${FUNCNAME[0]}" "INFO" "Commands $command_to_check_for is not found."
  return $FAILURE
}

#-------------------------
# ### System functions ###
#-------------------------

function get_disks () {
  # Gets the disk on the system.  It tries to get the most accurate and comprehensive
  # list of disks depending upon the commands available on the machine.

  log_info "${FUNCNAME[0]}" "INFO" "Generating a list of all disks on the system."

  is_command_available geom
  if [[ $? -eq $SUCCESS ]]; then
    log_info "${FUNCNAME[0]}" "INFO" "geom command available."
    DISKS=$(geom disk list | grep Name | awk '{print $3}')
  else
    command_avail lsblk;
    if [[ $? -eq $SUCCESS ]]; then
      log_info "${FUNCNAME[0]}" "INFO" "lsblk command available."
      DISKS=$(lsblk -dp | grep -o '^/dev[^ ]*')

    else
     log_info "${FUNCNAME[0]}" "ERROR" "No disks found.  Aborting."
     err "No disk found.  Aborting."
     exit $FAILURE
    fi
  fi

  LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")
  if [[ -z $LIST_OF_DISKS ]]; then
    log_info "${FUNCNAME[0]}" "ERROR" "No disks found.  Aborting."
     err "No disk found.  Aborting."
    exit $FAILURE
  fi
  return $SUCCESS
}

function get_sys_info () {
  # Gets systeminformation and fills in the global variables

  UPTIME=$(uptime | awk '{ print $3, $4, $5 }' | sed 's/,//g' | sed 's/\r//g')
  ARCH_TYPE=$(uname -m)
  PROC_TYPE=$(uname -p)
  OS_TYPE=$(uname -s)
  OS_VER=$(uname -o)
  OS_REL=$(uname -r)
}

function print_sys_info () {
  # Prints out simple system information

  case $O_FORMAT in
    html) 
      print_raw "<p>"
      print_raw "<b>Host name:       </b> $HOSTNAME"
      print_raw "<b>System Uptime:   </b> $UPTIME" 
      print_raw "<b>Arch Type:       </b> $ARCH_TYPE" 
      print_raw "<b>Procesor Type:   </b> $PROC_TYPE" 
      print_raw "<b>OS Version:      </b> $OS_VER" 
      print_raw "<b>OS Release:      </b> $OS_REL"
      print_raw "</p>"
      ;;

    text)
      local fmt="%-29s%-22s%29s\n"
      draw_separator
      printf "$fmt" "|" "System Information" "|" >> $O_FILE
      draw_separator
      fmt="| %-19s%-19s %-19s%-19s|\n"
      printf "$fmt" "Host Name:"  "$HOSTNAME"  "System Uptime:" "$UPTIME" >> $O_FILE
      printf "$fmt" "Arch Type:"  "$ARCH_TYPE" "Procesor Type:" "$PROC_TYPE" >> $O_FILE
      printf "$fmt" "OS Version:" "$OS_VER"    "OS Release:"    "$OS_REL" >> $O_FILE
      draw_separator
  esac

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
  if [ $DEBUG == "y" ]; then 
    printf "%(%m-%d-%Y %H:%M:%S)T\t%s\t%s\t%s\t%s\n" $(date +%s) "$0 ${FUNCNAME[0]} $1 $2 $3"
  fi; 
  return $SUCCESS
}

#----------------------------------
### Text based Output Functions ###
#----------------------------------
function draw_separator () {
  # Prints out a character separator line

  local output_char="#"
  local num_chars=200
  
#  if [[ -z $num_chars ]]; then
#    num_chars=80
#  fi

#  if [[ -z output_char ]]; then
#    output_char="#"
#  fi

  local output_line=$(printf "$output_char%.0s" `(seq 1 $num_chars)`; echo)
  echo $output_line  >> ${O_FILE}
}

function draw_row () {
  for i in "$@"; do
    printf "%20.20s" "$i" >> ${O_FILE}
  done
  printf "\n" >> ${O_FILE}
  draw_separator
  return $SUCCESS
}

#------------------------------
# ### HTML Output Functions ###
#------------------------------
function start_table () {
  echo "<table id="storage" border=2 cellpadding=4>" >> ${O_FILE}
}

function end_table () {
  echo "</table>" >> ${O_FILE}
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
  start_row
  for i in "$@"; do
    print_td "$i"
  done
  end_row
  return $SUCCESS
}

#---------------------
### Misc functions ###
#---------------------
function end_table () {
  case $O_file in
    html)
     print_raw "</table>"
     ;;
    text)
      draw_separator
      ;;
  esac
}


function check_paramcondition () {
  local param_to_check=$1
  local param_warn=$2
  local param_err=$3
}

#-------------------------
### Document functions ###
#-------------------------

function create_mail_header () {
#  Create the email header

  # NB: check to see if destination file can be created

  (
    echo To: $EMAIL_TO
    echo Subject: $MAIL_SUBJECT
    echo Content-Type: text/html
    echo MIME-Version: 1.0
  ) > ${O_FILE}
  return $SUCCESS
}

function create_results_header () {
  case $O_FORMAT in
    html) 
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
      print_raw "<h1>Status for Disks Found on $HOST_NAME on $(date "+%Y-%m-%d")</h1>"
      print_sys_info

      print_raw "<table id="storage" border=2 cellpadding=4>"
      print_row "Device" "Type" "Serial #" "Model" "Capacity" "Speed" "Current Speed" "Hours Powered On" "Start/Stop Count" \
                "End to End Errors" "Spin Retries" "Command Timeouts" "Last Test" "Reallocated Sectors" "Temp"
      ;;

    text)
      print_sys_info
      fmt="%-5.5s %-7.7s %-20.20s %-20.20s %-10.10s %-8.8s %-8.8s %-10.10s %-10.10s %-10.10s %-10.10s %-10.10s %-10.10s %-10.10s %-5.5s\n"
      printf "$fmt" "Device" "Type" "Serial #" "Model" "Capacity" "Max" "Current" "Hours" "Start/Stop" \
                "End to End" "Spin" "Command" "Last Test" "Realloc" "Temp" >> ${O_FILE}
      printf "$fmt" " " " " " " " " " " "Speed" "Speed" "Powered On" "Count" \
                "Errors" "Retries" "Timeouts" "Results" "Sectors" "Temp" >> ${O_FILE}
      draw_separator
      ;;
  esac
  return $SUCCESS
}

function end_document () {

#  End the HTML document properly
  case $O_FILE in
    html) 
      print_raw "</body></html>" 
      ;;
    text) 
      print_raw "" 
      ;;
  esac
}

#------------------------------
### Main script starts here ###
#------------------------------

##### Check for min versions  #####
if [[ $BASH_MIN_VER != $BASH_CUR_VER ]]; then
  err "This script requires at least BASH $BASH_MIN_VER."
  exit 1
fi

while getopts 'de:f:m:s:o:' arg; do
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

    m)
      MAIL_FILE="$OPTARG"
      ;;

    s)
      EMAIL_SUBJECT="$OPTARG"
      ;;

    o)
      O_FORMAT="$OPTARG"
      ;;

    h)
      printf "\n%s\n\n" "Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y | n] [-s subject] [-o html | text]"
      exit 1
      ;;

    :)
      printf "\n\t %s %s %s" "Illegal option: " $OPTARG "requires an argument"
      exit 1
      ;;
  esac
done
shift "$((OPTIND -1))"

# Verify that the options are correct

if test -f "$O_FILE"; then
  log_info "${FUNCNAME[0]}" "INFO" "$O_FILE exists.  Deleting."
  rm $O_FILE
fi

check_avail_commands "${ALL_CMDS[@]}"
get_sys_info
create_mail_header
create_results_header
get_disks

#  Cycle thrrough the disks and collect data dependent upon what type

log_info "${FUNCNAME[0]}" "INFO" "Iterrating through disks."
for i in $LIST_OF_DISKS 
  do
    #  Reset all the variables to blank
    max_speed="    Gb/s"
    cur_speed="    Gb/s"
    ser_num="-"
    model="-"
    dev_type="UKN"
    capacity="     xB"
    pwr_on_hrs="-"
    start_stop_ct="-"
    total_seeks="-"
    spin_errors="-"
    cmd_errors="-"
    test_results="-"
    bad_sectors="-"
    temp="-"

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
      dev_type="O/L"
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

      USB)
        full_results=$(smartctl -a -d scsi /dev/$i)
        model=$(grep 'Product'                        <<< $full_results | awk '/Product/               {print $2, $3, $4}')
        capacity=$(grep       'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5, $6}' | sed -e 's/^.//' -e 's/.$//')
        ser_num=$(grep        'Vendor:'               <<< $full_results | awk '/Vendor:/               {print $3}')
        start_stop_ctq=$(grep     'Power_Cycle_Count'     <<< $full_results | awk '/Power_Cycle_Count/     {print $10}')
        test_results="-"
        bad_sectors="-"
        temp="-"
        ;;

      OFFLINE)
        log_info "${FUNCNAME[0]}" "INFO" "Disk is offline."
        ;;

      *)
        log_info "${FUNCNAME[0]}" "INFO" "Unknown disk type"
        ;;
    esac

    #  Print out the collected data
    case $O_FORMAT in
      html)
        print_row "$i" "$dev_type" "$ser_num" "$model" "$capacity" "$max_speed" "$cur_speed" \
              "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" \
              "$spin_errors" "$cmd_errors" "$test_results" "$bad_sectors" "$temp"
        ;;

      text)
        fmt="%-5.5s %-7.7s %-20.20s %-20.20s %10.10s %-8.8s %-8.8s %10.10s %10.10s \
             %10.10s %10.10s %-10.10s %10.10s %10.10s %5.5s\n"
        printf "$fmt" "$i" "$dev_type" "$ser_num" "$model" "$capacity" "$max_speed" "$cur_speed" \
               "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" \
               "$spin_errors" "$cmd_errors" "$test_results" "$bad_sectors" "$temp" \
                >> ${O_FILE}
        ;;
    esac

 done

end_table
end_document

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

exit $SUCCESS



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
