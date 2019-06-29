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
# ---

# --- Global Variables
DEBUG="n"
MAIL_FILE="y"
O_FILE="/tmp/disk_overview.html"
EMAIL_TO="user@company.com"
HOST_NAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME"
DISKS=$(geom disk list | grep Name | awk '{print $3}')
LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")

# --- Useful functions ---
function print_td () { echo "<td>$1</td>" >> ${O_FILE}; }
function print_raw () { echo $1 >> ${O_FILE}; }
function start_row () { echo "<tr>" >> ${O_FILE}; }
function end_row () { echo "</tr>" >> ${O_FILE}; }
function LOG() { if [ $DEBUG == "y" ]; then printf "%(%m-%d-%Y %H:%M:%S)T\t%s\t%s\t%s\n" $(date +%s) "$0 $1 $2"; fi; }

function print_row() {
  LOG "INFO" "Number of variables passed to ${FUNCNAME} was: $#"
  expected_inputs=13
  if [ $expected_inputs -ne $# ]; then
    echo "ERROR -- ${FUNCNAME} -- Incorrect number of parameters passed."
    for i in "$@"; do
      echo "$i..."
    done
    exit -1
  fi
  start_row
  for i in "$@"; do
    print_td "$i"
  done
  end_row
}

# --- Parse the command line arguments ---

while getopts 'de:f:m:s:' arg; do
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
    h)
        printf "\n%s\n\n" "Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y/n] [-s subject] "
        exit 1
        ;;
    m)
        MAIL_FILE="$OPTARG"
        ;;
    s)
        EMAIL_SUBJECT="$OPTARG"
        ;;
    ?)
        printf "\n%s\n\n" "Usage: $(basename $0): [-d] [-e email address] [-f filename] [-m y/n] [-s subject] "
        exit 1
        ;;
    :)
        printf "\n\t %s %s %s" "Illegal option: " $OPTARG "requires an argument"
        exit 1
        ;;
  esac
done
shift "$((OPTIND -1))"

LOG "INFO" "Starting the disk check script ..."

# --- Create the email header ---
(
echo To: $EMAIL_TO
echo Subject: $MAIL_SUBJECT
echo Content-Type: text/html
echo MIME-Version: 1.0
) > ${O_FILE}

# --- Create the HTML PAGE portion ---
print_raw "<!DOCTYPE html>"
print_raw "<html>"
print_raw "<head>"
print_raw "<style>"
print_raw "<body {font-family: verdana; font-size: 10px; color: black}>"
print_raw "</style>"
print_raw "</head>"
print_raw "<body>"

# --- Print out the short status of the zpools ---
#print_raw "<h1>Zpool Summary</h1>"
#print_raw "<pre>"
#zStatus=$(zpool list -T d -v)
#print_raw "$zStatus"
#print_raw "</pre>"

# --- Create an HTML Table of the results.  This tends to read better on mail readers and phones than ---
# --- just outputing formatted text. ---

print_raw "<h1>SMARTCTL Status for Disks Found</h1>"
print_raw "<table>"
print_row "DISK" "Serial #" "MODEL" "TYPE" "CAPACITY" "Hours Powered On" "Start/Stop Count" "Total Seeks" "Seek Errors" \
           "Command Timeouts" "TEST STATUS" "BAD SECTORS" "TEMP"


# --- Cycle thrrough the disks and collect data dependent upon what type

LOG "INFO" "Iterrating through disks..."
for i in $LIST_OF_DISKS 
  do
    ser_num=99
    model=98
    dev_type="UNK"
    capacity="xxxGB"
    pwr_on_hrs=97
    start_stop_ct=96
    total_seeks=96
    seek_errors=94
    cmd_errors=93
    test_results=92
    bad_sectors=90
    temp=0

    # --- Just do the smartctl call once if possible

    full_results=$(smartctl -a /dev/$i)
    ssd_dev=$(grep 'Solid State Device' <<< $full_results)
    usb_dev=$(grep 'USB bridge' <<< $full_results)
    offline_dev=$(grep 'INQUIRY failed' <<< $full_results)

    # --- Try to classify the device type
    if [[ -n "${ssd_dev/[ ]*\n}" ]]; then
      dev_type="SSD"
    elif [[ -n "${usb_dev/[ ]*\n/}" ]]; then
      dev_type="USB"      
    elif [[ -n "${offline_dev/ [ ]*\n}" ]]; then
      dev_type="OFFLINE"
    else
      dev_type="HDD"
    fi
    LOG "INFO" "Examing device $i which is $dev_type device."

    # --- For each of the device types, collect the appropriate information
    case $dev_type in
      HDD)
        ser_num=$(grep       'Serial Number'         <<< $full_results | awk '/Serial Number/         {print $3}')
        model=$(grep         'Device Model'          <<< $full_results | awk '/Device Model/          {print $3 $4}')
        capacity=$(grep      'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5 $6}')
        pwr_on_hrs=$(grep    'Power_On_Hours'        <<< $full_results | awk '/Power_On_Hours/        {print $10}')
        start_stop_ct=$(grep 'Start_Stop_Count'      <<< $full_results | awk '/Start_Stop_Count/      {print $10}')
        total_seeks=$(grep   'Power_On_Hours'        <<< $full_results | awk '/Power_On_Hours/        {print $10}')
        seek_errors=$(grep   'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        cmd_errors=$(grep    'Command_Timeout'       <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        test_results=$(grep  'test result'           <<< $full_results | awk '/test result/           {print $6}')
        bad_sectors=$(grep   'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        temp=$(grep          'Temperature_Celsius'   <<< $full_results | awk '/Temperature_Celsius/   {print $10}')
        ;;
 
      SSD)
        LOG "INFO" "Collecting information for SDD type disk"
        ser_num=$(grep       'Serial Number'         <<< $full_results | awk '/Serial Number/         {print $3}')
        model=$(grep         'Device Model'          <<< $full_results | awk '/Device Model/          {print $3 $4}')
        capacity=$(grep      'User Capacity'         <<< $full_results | awk '/User Capacity/         {print $5 $6}')
        pwr_on_hrs=$(grep    'Power_On_Hours'        <<< $full_results | awk '/Power_On_Hours/        {print $10}')
        start_stop_ct=$(grep 'Start_Stop_Count'      <<< $full_results | awk '/Start_Stop_Count/      {print $10}')
        total_seeks=$(grep   'Power_On_Hours'        <<< $full_results | awk '/Power_On_Hours/        {print $10}')
        seek_errors=$(grep   'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        cmd_errors=$(grep    'Command_Timeout'       <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        test_results=$(grep  'test result'           <<< $full_results | awk '/test result/           {print $6}')
        bad_sectors=$(grep   'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
        temp=$(grep          'Temperature_Celsius'   <<< $full_results | awk '/Temperature_Celsius/   {print $10}')
        ;;

      USB)
        LOG "INFO" "Collecting information for USB type disk"
        full_results=$(smartctl -a -d scsi /dev/$i)
        model=$(grep 'Product' <<< $full_results | awk '/Product/ {print $2}')
        test_results="N/A"
        bad_sectors="N/A"
        temp="N/A"
        ;;

      OFFLINE)
        LOG "INFO" "Disk is offline."
        ;;

      *)
        LOG "INFO" "Unknown disk type"
        ;;
    esac

    # --- Print out the table row
#    print_row $i $ser_num $model $dev_type $capacity $pwr_on_hrs $start_stop_ct $total_seeks $seek_errors $cmd_errors $test_results $bad_sectors $temp
    print_row "$i" "$ser_num" "$model" "$dev_type" "$capacity" "$pwr_on_hrs" "$start_stop_ct" "$total_seeks" "$seek_errors" "$cmd_errors" "$test_results" "$bad_sectors" "$temp"

 done



print_raw "</table>"

# --- End the HTML document properly
print_raw "</body>"
print_raw "</html>"

# --- Send the file if required. ---

if [ $MAIL_FILE != "n" ]
then
  LOG "INFO" "Sending the report to $EMAIL_TO"
  sendmail -t < $O_FILE
else
  LOG "INFO" "Not sending file"
fi

# --- Clean up 
LOG "INFO" "Cleaning up."

if [ $DEBUG = "n" ]
then
  LOG "INFO" "Deleting $O_FILE."
  rm $O_FILE
fi

LOG "INFO" "Ending the disk checking script"
exit 0
