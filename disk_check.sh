#!/bin/bash
#
# Description:
#   A simple script to collect some information about the disks on the freenas server.  The data
#   is stored in a file and setup to enable mailing of the file.
# Usage:
#   sh disk_check.sh command arguments
#   where:
#     --debug 
#     --email=email_address
#     --help
#     --no-mail 
#
echo $(date) "Starting the disk check script ..."


# --- Global Variables ---
MAIL_FILE=true
O_FILE=/tmp/disk_overview.html
EMAIL_TO="hunterdp@gmail.com"
HOST_NAME=$(hostname -s | tr '[:lower:]' '[:upper:]')
MAIL_SUBJECT="FreeNAS SMART and Disk Summary for $HOST_NAME"
DISKS=$(geom disk list | grep Name | awk '{print $3}')
LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")

# --- Parse the command line arguments ---

while getopts :dne:
do 
  case $name in
    d )  
        DEBUG=true
        ;;
    e ) 
        EMAIL_TO="$OPTARG"
        ;;
    n )
        MAIL_FILE=false
        ;;
    \? )
        printf "Usage: %s: [-d] [-e email address] [-n] args \n" $0
        exit 1
        ;;
    : ) 
        echo "Invalid option: $OPTARG requires an argument" 1>&2
  esac
done
shift $((OPTIND -1))

echo $(date) "$DEBUG == $EMAIL_TO == $MAIL_FILE"

#for argument in "$@"
#do
#  if [ "$argument" == "--debug" ]
#  then
#    DEBUG=1
#
#  elif [ "$argument" == "--no-mail" ]
#  then
#    MAIL_FILE=false
#
#  elif [ "$argument" == "--help" ] || [ "$argument" == "-h" ]
#  then
#    printf "%s\n" "usage: disk_check.sh command args"
#    printf "%s\n\n" "Where:"
#    printf "\t%s\n" "--debug"
#    printf "\t%s\n" "--help or -h"
#    printf "\t%s\n" "--no-mail"
#    printf "\n"
#    exit 0;
#  fi
#done

# --- Useful functions ---
print_td () { echo "<td>$1</td>" >> ${O_FILE}; }
print_raw () { echo $1 >> ${O_FILE}; }
start_row () { echo "<tr>" >> ${O_FILE}; }
end_row () { echo "</tr>" >> ${O_FILE}; }

# --- Create the email header ---
(
echo To: $EMAIL_TO
echo Subject: $MAIL_SUBJECT
echo Content-Type: text/html
echo MIME-Version: 1.0
echo "<html>" 
) > ${O_FILE}

# Print out the short status of the zpools
print_raw "<h1>Zpool Summary</h1>"
print_raw "<pre style='font-size':14px>"
zStatus=$(zpool list -T d -v)
print_raw $zStatus
print_raw "</pre>"


# Create an HTML Table of the results.  This tends to read better on mail readers and phones than
# just outputing formatted text.

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

echo $(date) "Iterrating through disks..."

for i in $LIST_OF_DISKS 
  do
    full_results=$(smartctl -a /dev/$i)

    # Check to see if it is a USB device and set the device type to scsi
    # NB: USB devices generally do not support SMART

    usb_dev=$(grep 'USB bridge' <<< $full_results)
    if [[ -n "${usb_dev/[ ]*\n/}" ]]
    then
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

# Close the file and send it
print_raw "</html>"

if $MAIL_FILE 
then
  echo $(date) "Sending the report ..."
  # sendmail -t < $O_FILE
fi

echo $(date) "Ending the disk checking script"
exit 0
