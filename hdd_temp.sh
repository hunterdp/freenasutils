#!/bin/sh
# Display current temperature of CPU(s) and all SMART-enabled drives

# Full path to 'smartctl' program:
smartctl=/usr/local/sbin/smartctl

# We need a list of the SMART-enabled drives on the system. Choose one of these
# three methods to provide the list. Comment out the two unused sections of code.
#
# 1. A string constant; just key in the devices you want to report on here:
#drives="da1 da2 da3 da4 da5 da6 da7 da8 ada0"

# 2. A systcl-based technique suggested on the FreeNAS forum:
#drives=$(for drive in $(sysctl -n kern.disks); do \
#if [ "$(/usr/local/sbin/smartctl -i /dev/${drive} | grep "SMART support is: Enabled" | awk '{print $3}')" ]
#then printf ${drive}" "; fi done | awk '{for (i=NF; i!=0 ; i--) print $i }')

# 3. A smartctl-based function:
#
get_smart_drives()
{
  gs_smartdrives=""
  gs_drives=$("$smartctl" --scan | awk '{print $1}')

  for gs_drive in $gs_drives; do
    gs_smart_flag=$("$smartctl" -i "$gs_drive" | egrep "SMART support is:[[:blank:]]+Enabled" | awk '{print $4}')
    if [ "$gs_smart_flag" = "Enabled" ]; then
      gs_smartdrives="$gs_smartdrives $gs_drive"
    fi
  done
  echo "$gs_smartdrives"
}

drives=$(get_smart_drives)

# Get CPU information
 
cpucores=$(sysctl -n hw.ncpu)
printf '=== CPU (%s) ===\n' "$cpucores"
cpucores=$((cpucores - 1))
for core in $(seq 0 $cpucores); do
  temp=$(sysctl -n dev.cpu."$core".temperature|sed 's/\..*$//g')
  if [ "$temp" -lt 0 ]; then
    temp="--n/a--"
  else
    temp="${temp}C"
  fi
  printf 'CPU %2.2s: %5s\n' "$core" "$temp"
done
echo ""

# Get Drive Information
echo "=== DRIVES ==="
for drive in $drives; do
  serial=$("$smartctl" -i "$drive" | grep -i "serial number" | awk '{print $NF}')
  capacity=$("$smartctl" -i "$drive" | grep "User Capacity" | awk '{print $5 $6}')
  temp=$("$smartctl" -A "$drive" | grep "194 Temperature" | awk '{print $10}')
  if [ -z "$temp" ]; then
    temp=$("$smartctl" -A "$drive" | grep "190 Airflow_Temperature" | awk '{print $10}')
  fi
  if [ -z "$temp" ]; then
    temp=$("$smartctl" -A "$drive" | grep "Current Drive Temperature" | awk '{print $4}')
  fi
  if [ -z "$temp" ]; then
    temp="-n/a-"
  else
    temp="${temp}C"
  fi
  dfamily=$("$smartctl" -i "$drive" | grep "Model Family" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
  dmodel=$("$smartctl" -i "$drive" | grep "Device Model" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
  if [ -z "$dfamily" ]; then
    dinfo="$dmodel"
  else
    dinfo="$dfamily ($dmodel)"
  fi
  if [ -z "$dfamily" ]; then
    vendor=$("$smartctl" -i "$drive" | grep "Vendor:" | awk '{print $NF}')
    product=$("$smartctl" -i "$drive" | grep "Product:" | awk '{print $NF}')
    revision=$("$smartctl" -i "$drive" | grep "Revision:" | awk '{print $NF}')
    dinfo="$vendor $product $revision"
  fi
  printf '%6.6s: %5s %-8s %-20.20s %s\n' "$(basename "$drive")" "$temp" "$capacity" "$serial" "$dinfo" 
done