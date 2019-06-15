#!/bin/bash
# Description:
#   A simple script to send a formatted email regarding the status of disks based upon smartctl.
#   Place this in  location for administrative scripts and then setup a cron job to execute.
# Usage:
#   sh disk_check.sh
# ToDo:
#   Make things more readable and use more variables for output file and disks.

# generate a list of disks on the host
LIST_OF_DISKS=$(geom disk list | grep Name | awk '{print $3}')

# TBD: specify any disks to exclude
EXCLUDE_DISKS=""

o_file="./tmp/cover.html"

# setup the mail header.
(
echo “To: receiver@domain.tld”
echo “Subject: SMART Drive Results for all drives”
echo “Content-Type: text/html”;
echo “MIME-Version: 1.0″;
echo ” ”
echo “<html>”
)>tmp/cover.html

#
# For each device, look for bad sectors and get the disk temperature.
#
#c=0
#for i in /dev/da0 /dev/da1 /dev/da2 /dev/da3 /dev/da4 /dev/da5 /dev/da6 /dev/da6 /dev/da7 /dev/da8 /dev/da9 /dev/ada0 /dev/ada01 /dev/ada02 /dev/ada03; do

#  results=$(smartctl -i -H -A -n standby -l error $i | grep -i 'test result’)
#  badsectors=$(smartctl -i -H -A -n standby -l error $i | grep -i ‘Reallocated_Sector’ | awk ‘/Reallocated_Sector_Ct/ {print $10}’)
##  temperature=$(smartctl -i -H -A -n standby -l error $i | grep -i ‘Temperature_Celsius’ | awk ‘/Temperature_Celsius/ {print $10}’)
#  temperature=$(smartctl -i -H -A -n standby -l error $i | grep -i Temperature_Celsius | awk '/Temperature_Celsius/ {print $10}')
#  ((c=c+1))
# echo $c
#  echo "Disk: $i"
#  echo "$results"

#  if [[ $results == *”PASSED”* ]]
#  then
#    status[$c]=”Passed”
#    color=”green”
#  else
#    status[$c]=”Failed”
#    color=”red”
#  fi

#  echo “$i status is ${status[$c]} with $badsectors bad sectors. Disk temperature is $temperature.”
#  echo “<div style=’color: $color’> $i status is ${status[$c]} with $badsectors bad sectors. Disk temperature is $temperature.</div>” > tmp/cover.html
#done

#echo “</html>” >> $o_file

#sendmail -t < ./tmp/cover.html

exit 0
