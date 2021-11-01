#!/bin/sh 
# AUTHOR:   David Hunter (dph@alumni.neu.edu)
#
# Shell script to run a clamav scan and prepare an email the results.
# Uses ssmtp to send the email.  The script assumes that ssmtp is setup
# correctly and uses the system-wide configurations.
#
# Currently, this does not move or isolate any infected files.  It just
# reports the infection.  For most cases this is fine and once the report
# is reviewed, the appropriate action can be taken.  This is the safest
# model for production systems.
#
# This is best placed in a cron job.  It does daily scans as well as a
# full system scan (/) once a week on the defined date.
# 

##----------------------------------- ##
## Modify these to fit your use case. ##
##----------------------------------- ##
# The email receipient
TO_EMAIL="foo@gmail.com"

# The top level directories to scan.  The scan will travese the directory
DAILY_DIR_TO_SCAN="/home/"
WEEKLY_DIR_TO_SCAN="/"

# The location of the cland.conf file
CLAMD_CONF="/etc/clamav/clamd.conf"

# A list of directories to exclude from the scan.  This is only used by
# clamscan.  Note that this can be a regex expression.  For clamdscan, 
# edit the system config file and modify the ExcludePath variable. 
EXCLUDED_DIRS="--exclude-dir=/sys/ --exclude-dir=/proc/ --exclude-dir=/dev/ --exclude-dir=/netshare/ --exclude-dir=/ISO/ --exclude-dir=/media/"

# Either the clamscan or clamdscan command can be used.  Clamd uses multithreads and
# is preferred, and significantly faster on a multithreaded capable machine.  Change the 
# SCAND to 0 if you want to use clamscan.
SCAND=0

# The location of the tempory file created to store results that are emailed.
EMAIL_FILE="/tmp/clamd_email_results.tmp"

# The location of the scan log file.  This must be writable by the clamav process account
CLAMAV_LOG="/tmp/clamscan-$(date +'%Y-%m-%d-%H%M').log"

# The day of the week to do a weekly scan (Mon=1, Sun=7)
WEEKLY_SCAN_DOW=6

##----------------------------------- ##
## Do not change anyting below here   ##
##----------------------------------- ##
#TODAY=$(date +'%c')
HOST="$(hostname --fqdn)"
ERROR_FLAG=0

# Make sure we can write to the temporary files.
if ! touch $CLAMAV_LOG; then exit $?; fi
if ! touch $EMAIL_FILE; then exit $?; fi

# Set the subject of the email appropriately
if [ "$(date +'%u')" -eq $WEEKLY_SCAN_DOW ]; then
    EMAIL_SUBJECT="Weekly ClamAV Scan on ${HOST} started at: $(date +'%Y-%m-%d %H:%M:%S')"
else
    EMAIL_SUBJECT="Daily ClamAV Scan on ${HOST} started at: $(date +'%Y-%m-%d %H:%M:%S')"
fi

# Choose the command to use and its options..  
if [ $SCAND -eq 1 ]; then
    SCAN_COMMAND="clamdscan --quiet --multiscan --fdpass"
else
    SCAN_COMMAND="clamscan --recursive --allmatch --suppress-ok-results --infected ${EXCLUDED_DIRS} --quiet"
fi

# Remove any previous temporary files.
[ -f "$EMAIL_FILE" ] && rm $EMAIL_FILE

# Create the email message header.  
(
    echo "To: ${TO_EMAIL}"
    echo "Subject: ${EMAIL_SUBJECT}"
    echo ""
    echo "Run Summary "
    echo " Date: ${TODAY}"
    echo " Command: ${SCAN_COMMAND}"
) >> ${EMAIL_FILE}

# Check for required software.
if ! type ssmtp >/dev/null 2>&1; then
    echo "Required ssmtp not installed. Aborting." >> ${EMAIL_FILE}
    ERROR_FLAG=1
elif ! type clamdscan >/dev/null 2>&1; then
    echo "Require clamdscan it's not installed. Aborting." >> ${EMAIL_FILE}
    ERROR_FLAG=1
fi

# Verify the scan location.
if [ "$(date +'%u')" -eq $WEEKLY_SCAN_DOW ]; then
    if [ ! -d "$WEEKLY_DIR_TO_SCAN" ]; then
        echo "$WEEKLY_DIR_TO_SCAN does not exist. No scan performed." >> ${EMAIL_FILE}
        ERROR_FLAG=1
    else
        SIZE_OF_WEEKLY_DIR_TO_SCAN=$(du -shc $WEEKLY_DIR_TO_SCAN 2> /dev/null | cut -f1 | tail -1)
        echo " Directory Scanned: ${WEEKLY_DIR_TO_SCAN}" >> ${EMAIL_FILE}
        echo " Amount of data scanned: ${SIZE_OF_WEEKLY_DIR_TO_SCAN}" >> ${EMAIL_FILE}
    fi
else
    if [ ! -d "$DAILY_DIR_TO_SCAN" ]; then
        echo "$DAILY_DIR_TO_SCAN does not exist. No scan performed." >> ${EMAIL_FILE}
        ERROR_FLAG=1
    else
        SIZE_OF_DAILY_DIR_TO_SCAN=$(du -shc $DAILY_DIR_TO_SCAN 2> /dev/null | cut -f1 | tail -1)
        echo " Directory Scanned: ${DAILY_DIR_TO_SCAN}" >> ${EMAIL_FILE}
        echo " Amount of data scanned: ${SIZE_OF_DAILY_DIR_TO_SCAN}" >> ${EMAIL_FILE}
    fi
fi

# Run the anti-virus scan & process the results
if [ $ERROR_FLAG -eq 0 ]; then
    if [ "$(date +'%u')" -eq $WEEKLY_SCAN_DOW ]; then
        $SCAN_COMMAND --log=${CLAMAV_LOG} ${WEEKLY_DIR_TO_SCAN}
        scan_status=$?
    else
        $SCAN_COMMAND --log=${CLAMAV_LOG} ${DAILY_DIR_TO_SCAN}
        scan_status=$?
    fi
    scan_status=$?

    # Get the directories excluded in the scan when using clamdscan.
    echo " Excluded directories:" >> ${EMAIL_FILE}
    if [ $SCAND -eq 1 ]; then
        cat $CLAMD_CONF | grep 'ExcludePath' | sed 's/ExcludePath ^//' | awk '{print "   - " $0}' >> ${EMAIL_FILE}
    fi

    # Use the command status code to identify if any viruses were found.
    if [ $scan_status -eq 0 ]; then
        echo " Virus(es) Found: 0" >> ${EMAIL_FILE}
    elif [ $scan_status -eq 1 ]; then
        NUM_VIRUSES_FOUND=$(cat "${CLAMAV_LOG}" | grep "Infected files" | awk '{print $3}')
        echo " Virus(es) found: ${NUM_VIRUSES_FOUND}" >> ${EMAIL_FILE}
    elif [ $scan_status -eq 2 ]; then
        echo "Error code 2." >> ${EMAIL_FILE}
    else
        echo "Unknown effort: $scan_status" >> ${EMAIL_FILE}
    fi

    # Search for any errors, warnings or bad behavior. Seperate by official vs unofficial
    # signatures.
    RUN_TIME=$(cat "${CLAMAV_LOG}" | grep 'Time:')
    WARNINGS=$(cat "${CLAMAV_LOG}" | grep 'WARNING' | wc -l)
    ERRORS=$(cat "${CLAMAV_LOG}" | grep 'ERROR' | wc -l)
    INFECTED_COUNT=$(cat "${CLAMAV_LOG}" | grep 'FOUND' | wc -l)
    UNOFFICIAL=$(cat "${CLAMAV_LOG}" | grep 'UNOFFICIAL FOUND' | wc -l)
    OFFICIAL="$(($INFECTED_COUNT-$UNOFFICIAL))"

    echo " ${RUN_TIME}" >> ${EMAIL_FILE}
    if [ ! $ERRORS -eq 0 ]; then
        echo " Errors: ${ERRORS}" >> ${EMAIL_FILE}
    else
        echo " Errors: 0" >> ${EMAIL_FILE}

    fi

    if [ ! $WARNINGS -eq 0 ]; then
        echo " Warnings: ${WARNINGS}" >> ${EMAIL_FILE}
    else
        echo " Warnings: 0" >> ${EMAIL_FILE}
    fi

    if [ ! $INFECTED_COUNT -eq 0 ]; then
        (
            echo " Infected files: ${INFECTED_COUNT}"
            echo " Official signatures found: ${OFFICIAL}"
            echo " Unofficial signatures found: ${UNOFFICIAL}"
        ) >> ${EMAIL_FILE}

        if [ $OFFICIAL -gt 0 ]; then
            (
                echo "  --------------------"
                echo "  Official Found Files"
                echo "  --------------------"
                echo "$(cat $CLAMAV_LOG | grep 'FOUND' | grep -v 'UNOFFICIAL FOUND' | sed 's/FOUND//' | awk '{print "   - " $0}')"
                echo " "
            ) >> ${EMAIL_FILE}
        fi

        if [ $UNOFFICIAL -gt 0 ]; then
            (
                echo "  ---------------------"
                echo "  Unofficial Found Files"
                echo "  ---------------------"
                echo "$(cat $CLAMAV_LOG | grep 'UNOFFICIAL FOUND' | sed s/FOUND// | awk '{print "   - " $0}')"
                echo " "
            ) >> ${EMAIL_FILE}
        fi
    fi

    if [ $ERRORS -gt 0 ]; then
        (
            echo "  ---------------------------------"
            echo "  Error Descriptions (de-dplicated)"
            echo "  ---------------------------------"
            echo "$(cat $CLAMAV_LOG | grep 'ERROR' | sed s/ERROR// | uniq | awk '{print "   - " $0}')"
            echo " "
        ) >> ${EMAIL_FILE}
    fi

    if [ $ERRORS -gt 0 ]; then
        (
            echo "  ---------------------------------"
            echo "  Warning Descriptions (de-dplicated)"
            echo "  ---------------------------------"
            echo "$(cat $CLAMAV_LOG | grep 'WARNING' | sed s/WARNING// | uniq | awk '{print "   - " $0}')"
            echo " "
        ) >> ${EMAIL_FILE}
    fi

    if [ ! $scan_status -eq 0 ]; then    
        (
            echo " "
            echo "--------------------------------------"
            echo "clamav log file"
            cat "${CLAMAV_LOG}"
        ) >> ${EMAIL_FILE}
    fi
fi

# email the results.
ssmtp ${TO_EMAIL} < $EMAIL_FILE