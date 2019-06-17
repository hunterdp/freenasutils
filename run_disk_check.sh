#!/bin/sh

# A simple script to run the disk checking script in a jail.
# NB: Need to add some basc error checking and reporting.

# Define the location where the "avscan.sh" shell script is located on the jail:
scriptlocation="/mnt/Sysadmin/scripts/"

# Execute the script 
# We are using the already established clamav jail.
iocage exec clamav "$scriptlocation"disk_check.sh

## email the log ##
sendmail -t < /mnt/r10-vol2/Sysadmin/scripts/disk_overview.html

## Delete the log file ##
rm /mnt/r10-vol2/Sysadmin/scripts/disk_overview.html
