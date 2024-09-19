#!/bin/bash

# Retrieve a list of Proxmox VMs using 'qm list'
vm_list=$(qm list | tail -n +2)  # Skipping the first header line

# Check if any VMs are available
if [ -z "$vm_list" ]; then
    echo "No Proxmox VMs found."
    exit 1
fi

# Prepare VM options for the radio list (single selection)
vm_options=()
while IFS= read -r vm; do
    vm_id=$(echo "$vm" | awk '{print $1}')
    vm_name=$(echo "$vm" | awk '{print $2}')
    vm_options+=("$vm_id" "$vm_name" OFF)
done <<< "$vm_list"

# Get a list of all connected SSDs and HDDs (logical names)
devices=$(lsblk -d -o NAME,TYPE,TRAN | grep -E 'disk' | awk '{print $1}')

# Check if there are no devices found
if [ -z "$devices" ]; then
    echo "No SSD or HDD devices found."
    exit 1
fi

# Create an array to store device options for whiptail (only logical names are displayed)
options=()
for device in $devices; do
    device_paths["$device"]="/dev/$device"
    options+=("$device" "" "")  # Only display the logical device name
done

# Display the checkbox dialog for device selection (showing only logical names)
selected_devices=$(whiptail --title "Select Devices" --checklist \
"Choose devices to select (use space to select and enter to confirm):" 15 50 6 \
"${options[@]}" 3>&1 1>&2 2>&3)

# Check if the user made a selection
if [ -z "$selected_devices" ]; then
    echo "No devices selected."
    exit 1
fi 

# Display the radio list dialog for Proxmox VM selection (only one VM can be selected)
selected_vm=$(whiptail --title "Select a Proxmox VM" --radiolist \
"Choose a VM to select (use space to select and enter to confirm):" 15 50 6 \
"${vm_options[@]}" 3>&1 1>&2 2>&3)

# Check if the user made a selection
if [ -z "$selected_vm" ]; then
    echo "No VM selected."
    exit 1
else
    # Get the name of the selected VM
    selected_vm_name=$(qm list | awk -v id="$selected_vm" '$1 == id {print $2}')

    # Show a confirmation box
    if whiptail --title "Confirmation" --yesno "You selected VM ID: $selected_vm (Name: $selected_vm_name). Is this correct?" 10 60; then
        echo "Confirmed: VM ID $selected_vm (Name: $selected_vm_name)"
    else
        echo "Selection canceled."
        exit 1
    fi
fi

echo "Passing Sellected Disks to Selected VM."
number=1
# Loop through selected devices and print their corresponding by-id path
for device in $(echo $selected_devices | tr -d '"'); do
    path=$(find /dev/disk/by-id/ -type l|xargs -I{} ls -l {}|grep -v -E '[0-9]$' |sort -k11|cut -d' ' -f9,10,11,12 | grep -w "${device}")
    IFS=' ' read -r id string <<< "$path"
    qm set $selected_vm -scsi$number $id
    let "number++"
done
