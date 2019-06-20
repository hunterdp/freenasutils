#!/bin/bash
#
# Description:
#   A simple script to collect some information about the disks on the freenas server.  The data
#   is stored in a file and setup to enable mailing of the file.
# Usage:
#   sh disk_check.sh
#

echo $(date) "Starting the disk check script ..."
# Set this to the location where you want to store the temporary results file.
O_FILE=/tmp/disk_overview.html

# Setup the mail header.  Replace the address with your own and modify subject line
(
echo To: hunterdp@gmail.com
echo Subject: FreeNAS SMART and Disk Summary
echo Content-Type: text/html
echo MIME-Version: 1.0
echo "<html>" 
echo "<title>Summary of Freenas host $host </title>"
) > $O_FILE

# Print out the short status of the zpools
echo "<h1>Zpool Summary</h1><pre>" >> $O_FILE
zpool list -T d -v >> $O_FILE
echo "</pre><br>" >> $O_FILE

# Loop through the list of disks and retrieve various information
DISKS=$(geom disk list | grep Name | awk '{print $3}')
LIST_OF_DISKS=$(sort <<<"${DISKS[*]}")

echo "<h1>SMARTCTL Status for Disks Found</h1>" >> $O_FILE
echo "<table>" >> $O_FILE
echo "<tr>" >> $O_FILE
echo "<th>DISK</th>" >>$O_FILE
echo "<th>MODEL</th>" >> $O_FILE
echo "<th>TEST STATUS</th>" >> $O_FILE
echo "<th>BAD SECTORS</th>" >> $O_FILE
echo "<th>TEMPERATURE</th>" >> $O_FILE
echo "</tr>" >> $O_FILE

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

  echo "<tr>" >> $O_FILE
  echo "<td>$i</td>" >> $O_FILE 
  echo "<td>$model</td>" >> $O_FILE 
  echo "<td>$test_results</td>" >> $O_FILE
  echo "<td>$bad_sectors</td>" >> $O_FILE
  echo "<td>$temp degC</td>" >> $O_FILE
  echo "</tr>" >> $O_FILE 
done
echo "</table>" >> $O_FILE

# Close the file and send it
echo "</html>" >> $O_FILE

echo $(date) "Sending the report ..."
sendmail -t < $O_FILE

echo $(date) "Ending the disk checking script"
exit 0
