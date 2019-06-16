# freenasutils
Misc utilities used for managing and monitoring FreeNAS

* disk_check.sh - Looks at all disks on the system and sends a quick SMART status to an email address
* avscan.sh - Updates ClamAV definitions, runs a scan and then sends an email on the results.
* run_clamav_scan.sh - Used to run the avscan.sh script from cron.
