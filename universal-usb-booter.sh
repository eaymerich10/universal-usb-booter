#!/bin/bash

# ========================
# UNIVERSAL USB BOOTABLE CREATOR
# Author: Enric Aymerich
# Version: 1.0
# Description:
# This script formats a USB drive and writes any ISO file to it.
# making it bootable using the traditional 'dd' method.
# ========================


# --- Check if the script is being run as root ---
if [ "$EUID" -ne 0 ]; then
	echo "Please run this script as root using sudo."
	exit 1
fi

# --- Wipes existing filesystem signatures and creates a new partition table on a specified device ---
wipe_device() {
    local device="$1"  # Receives the device as an argument

    echo "🚀 Wiping signatures from $device with wipefs..."
    sudo wipefs -a "$device"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully wiped existing signatures from $device."
    else
        echo "❌ Failed to wipe existing signatures. Exiting..."
        exit 1
    fi

    echo "🚀 Creating a new partition table on $device..."
    
    # Creating a new partition table (MBR)
    echo -e "o\nw" | sudo fdisk "$device"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully created a new partition table on $device."
    else
        echo "❌ Failed to create a new partition table. Exiting..."
        exit 1
    fi
}


# --- Define the function to check if a partition is mounted ---
check_mounted() {
    local device="$1"
    local partitions=$(lsblk -ln -o NAME "$device" | grep -E "^${device/\/dev\//}" | grep -v "^$device$")
    local has_mounted=false

    for part in $partitions; do
        if sudo findmnt "/dev/$part" > /dev/null 2>&1; then
            echo "✅ /dev/$part is mounted. Attempting to unmount..."
            sudo umount "/dev/$part" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✅ Successfully unmounted /dev/$part."
            else
                echo "❌ Failed to unmount /dev/$part. Please close all programs using it and try again."
                exit 1
            fi
            has_mounted=true
        fi
    done

    # Check if the whole device is mounted (e.g., /dev/sda)
    if sudo findmnt "$device" > /dev/null 2>&1; then
        echo "✅ $device is mounted. Attempting to unmount..."
        sudo umount "$device" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "✅ Successfully unmounted $device."
        else
            echo "❌ Failed to unmount $device. Please close all programs using it and try again."
            exit 1
        fi
        has_mounted=true
    fi

    if [ "$has_mounted" = false ]; then
        echo "✅ No partitions were mounted on $device. Continuing..."
    fi
}

echo "=== UNIVERSAL USB BOOTABLE CREATOR ==="

# --- Ask confirmation to continue ---
read -p "This operation will erase your USB. Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
	echo "Aborted."
	exit 0
fi

# --- Display available disks ---
echo -e "\n Available disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
echo "-----------------------------------------------"

# --- Ask the user to input the USB device path ---
read -e -p "Enter  your USB device path (e.g., /dev/sdb): " usb

# --- Confirm the device again ---
read -p "You selected '$usb'. Are you sure? This will completely erase it. (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
	echo "Aborted"
	exit 0
fi

# --- Unmount any mounted partitions of the USB ---
echo "Unmounting all partitions of $usb..."
check_mounted "$usb"


# --- Wipe the USB drive completely ---
echo "Wiping the USB drive.. This may take a few minutes..."
wipe_device "$usb"

# --- Ask for the ISO file path ---
read -e -p "Enter the full path to the ISO file (use TAB for autocompletion): " iso

# --- Check that the ISO file exists ---
if [ ! -f "$iso" ]; then
	echo "ISO file not found at: $iso"
	exit 1
fi

# --- Check if the file is a valid ISO ---
echo "Checking if the file is a valid ISO..."
if ! file "$iso" | grep -q "ISO 9660"; then
	echo "Warning: The file doesn't appear to be a standard ISO image."
	read -p "Continue anyway (y/n): " confirm
	if [[ "$confirm" != "y" ]]; then
		echo "Aborted."
		exit 0
	fi
fi

# --- Write the ISO to the USE device using dd ---
echo "Writing the ISO to the USB device..."
dd if="$iso" of="$usb" bs=4M status=progress && sync

# -- Final check ---
if [ $? -eq 0 ]; then
	echo "Usb bootable drive created successfully!"
else
	echo "Something went wrong while writing the ISO."
fi 
