#!/bin/sh

## DPH - 20-Apr-2019
## - Copied from www.ixsystems.com/community/resources/how-to-install-clamav-on-freenas-v11.66/
## - Modified to add specific location of script and the name of the jail (clamav).
##
## DPH 21-Apr-2019
## - Cleaned up script and changed location to of file to send.
## - Will only work on FreeNAS 11.1 and higher.
##
## NB: Need to add some basc error checking and reporting.

## Define the location where the "avscan.sh" shell script is located on the jail:
scriptlocation="/mnt/Sysadmin/scripts/"

## Execute the script ##
iocage exec clamav "$scriptlocation"avscan.sh

## email the log ##
sendmail -t < /mnt/r10-vol2/Sysadmin/scripts/tmp/clamavemail.tmp

## Delete the log file ##
rm /mnt/r10-vol2/Sysadmin/scripts/tmp/clamavemail.tmp
