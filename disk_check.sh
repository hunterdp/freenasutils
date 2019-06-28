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

# --- Modify the behavior of the script to reduce errors and make sure all variables are defined.

#set -e
#set -u
#set -o pipefail

# --- Global Variables

DEBUG="n"
MAIL_FILE="y"
O_FILE="/tmp/disk_overview.html"
EMAIL_TO="user@company.com"
HOST_NAME=$(hostname -s | tr '[:lower:]' '[:upper:]')
MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME"
DISKS=$(geom disk list | grep Name | awk '{print $3}')
LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")

# --- Useful functions ---
print_td () { echo "<td>$1</td>" >> ${O_FILE}; }
print_raw () { echo $1 >> ${O_FILE}; }
start_row () { echo "<tr>" >> ${O_FILE}; }
end_row () { echo "</tr>" >> ${O_FILE}; }

DEBUG() { 
  # --- A simple function to print out some debugging data.  First variable is type 
  #     of information [INFO, WARN, ERROR] and second is the message to print out. ---
  if [ $DEBUG == "y" ] 
  then 
    printf "%(%m-%d-%Y %H:%M:%S)T\t%s\t%s\t%s\n" $(date +%s) "$0 $1 $2"
  fi
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

DEBUG "INFO" "Starting the disk check script ..."

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
print_raw "<body {font-family: verdana; font-size: 10px; color: black}</body>"
print_raw "</style>"
print_raw "</head>"
print_raw "<body>"

# --- Print out the short status of the zpools ---
print_raw "<h1>Zpool Summary</h1>"
print_raw "<pre>"
zStatus=$(zpool list -T d -v)
print_raw "$zStatus"
print_raw "</pre>"

# --- Create an HTML Table of the results.  This tends to read better on mail readers and phones than ---
# --- just outputing formatted text. ---

print_raw "<h1>SMARTCTL Status for Disks Found</h1>"
print_raw "<table>"
start_row
print_td "DISK"
print_td "Serial #"
print_td "Hours Powered On"
print_td "Start/Stop Count"
print_td "Total Seeks"
print_td "Seek Errors"
print_td "Command Timeouts"

print_td "MODEL"
print_td "TEST STATUS"
print_td "BAD SECTORS"
print_td "TEMPERATURE"
end_row

DEBUG "INFO" "Iterrating through disks..."

for i in $LIST_OF_DISKS 
  do
    DEBUG "INFO" "Examining disk $i"
    full_results=$(smartctl -a /dev/$i)

    # Check to see if it is a USB device and set the device type to scsi
    # NB: USB devices generally do not support SMART

    usb_dev=$(grep 'USB bridge' <<< $full_results)

    if [[ -n "${usb_dev/[ ]*\n/}" ]]
    then
      DEBUG "INFO" "$i is a USB Disk"
      full_results=$(smartctl -a -d scsi /dev/$i)
      model=$(grep 'Product' <<< $full_results | awk '/Product/ {print $2}')
      test_results="N/A"
      bad_sectors="N/A"
      temp="N/A"

    else
      model=$(grep 'Device Model' <<< $full_results |awk '/Device Model/ {print $3 $4}')
      test_results=$(grep 'test result' <<< $full_results | awk '/test result/ {print $6}')
      bad_sectors=$(grep 'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
      temp=$(grep 'Temperature_Celsius' <<< $full_results | awk '/Temperature_Celsius/ {print $10}')
    fi

    start_row
    print_td $i
    print_td $model 
    print_td $test_results
    print_td $bad_sectors
    print_td $temp
    end_row
 done
print_raw "</table>"

print_raw "</body>"
print_raw "</html>"

# --- Send the file if required. ---

if [ $MAIL_FILE != "n" ]
then
  DEBUG "INFO" "Sending the report to $EMAIL_TO"
  sendmail -t < $O_FILE
else
  DEBUG "INFO" "Not sending file"
fi

# --- Clean up 
DEBUG "INFO" "Cleaning up."

if [ $DEBUG = "n" ]
then
  DEBUG "INFO" "Deleting $O_FILE."
  rm $O_FILE
fi

DEBUG "INFO" "Ending the disk checking script"
exit 0
