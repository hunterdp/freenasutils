#!/bin/bash
#
# Description:
#   A simple script to send a formatted email regarding the status of disks based upon smartctl.
#   Place this in  location for administrative scripts and then setup a cron job to execute.
# Usage:
#   sh disk_check.sh
# ToDo:
#   Make the DEBUG a procedure
#

O_FILE=disk_overview.html

# Generate a list of disks on the host and ones to exclude
# NB:  We could use smartctl --scan but that will not list all the disks on the sytem.
LIST_OF_DISKS=$(geom disk list | grep Name | awk '{print $3}')
EXCLUDE_DISKS=""

# Setup the mail header.  Replace the address with your own and modify subject line
# if desired.
(
echo “To: me@myaddress.com”
echo “Subject: SMART Drive Results for all drives”
echo “Content-Type: text/html”
echo “MIME-Version: 1.0″
echo ” ”
echo "<html>"
) > $O_FILE

# Loop through the list of disks and retrieve various information

for i in $LIST_OF_DISKS 
do
  full_results=$(smartctl -a /dev/$i)

  # Check to see if it is a USB device and set the device type to scsi
  # NB: USB devices generally do not support SMART

  usb_dev=$(grep 'USB bridge' <<< $full_results)
  if [[ -n "${usb_dev/[ ]*\n/}" ]]
  then
    full_results=" "
    model="USB"
    test_results="N/A"
    bad_sectors="N/A"
    temp="N/A"

  else
    model=$(grep 'Device Model' <<< $full_results |awk '/Device Model/ {print $3 $4}')
    test_results=$(grep 'test result' <<< $full_results | awk '/test result/ {print $6}')
    bad_sectors=$(grep 'Reallocated_Sector_Ct' <<< $full_results | awk '/Reallocated_Sector_Ct/ {print $10}')
    temp=$(grep 'Temperature_Celsius' <<< $full_results | awk '/Temperature_Celsius/ {print $10}')
  fi

  echo "$i is a model $model with a status of $test_results and has $bad_sectors bad sectors.  Its temperature is $temp deg Celsius" >> $O_FILE    
  echo "i = $i"
done

# Close the file and send it
echo "</html>" >> $O_FILE

#sendmail -t < ./tmp/cover.html

exit 0
