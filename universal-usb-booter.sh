#!/bin/bash

# ========================
# UNIVERSAL USB BOOTABLE CREATOR
# Author: Enric Aymerich
# Version: 1.0
# Description:
# This script formats a USB drive and writes any ISO file to it,
# making it bootable using the traditional 'dd' method.
# ========================

# Colors for output messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Check if the script is being run as root ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root using sudo.${NC}"
    exit 6
fi

# --- Wipes existing filesystem signatures and creates a new partition table on a specified device ---
wipe_device() {
    local device="$1"

    echo "Wiping signatures from $device with wipefs..."
    sudo wipefs -a "$device"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully wiped existing signatures from $device.${NC}"
    else
        echo -e "${RED}Failed to wipe existing signatures. Exiting...${NC}"
        exit 3
    fi

    echo "🚀 Creating a new partition table and partition on $device..."
    # Creating a new partition table (MBR) and a primary partition
    echo -e "o\nn\np\n1\n\n\nw" | sudo fdisk "$device"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully created a new partition table and partition on $device.${NC}"
    else
        echo -e "${RED}Failed to create a new partition. Exiting...${NC}"
        exit 4
    fi
}

# --- Select USB device interactively using Bash's built-in 'select' ---
select_usb_device() {
    # Get USB devices and store them in an array
    IFS=$'\n' read -d '' -r -a devices < <(lsblk -dpno NAME,TRAN,SIZE | grep "usb")

    if [ ${#devices[@]} -eq 0 ]; then
        echo "❌ No USB devices detected. Please connect a USB drive and try again."
        exit 1
    fi

    # Display the selection menu with 'select'
    PS3="Select a device by number: "
    select device in "${devices[@]}"; do
        if [ -n "$device" ]; then
            # Capturar solo el nombre del dispositivo (/dev/sdX)
            selected_device=$(echo "$device" | awk '{print $1}')
            break
        else
            echo "❌ Invalid selection. Please try again."
        fi
    done

    echo "$selected_device"
}


# --- Define the function to check if a partition is mounted ---
check_mounted() {
    local device="$1"
    local partitions=$(lsblk -ln -o NAME "$device" | grep -E "^${device/\/dev\//}" | grep -v "^$device$")
    local has_mounted=false

    for part in $partitions; do
        if sudo findmnt "/dev/$part" > /dev/null 2>&1; then
            echo "/dev/$part is mounted. Attempting to unmount..."
            sudo umount "/dev/$part" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Successfully unmounted /dev/$part.${NC}"
            else
                echo -e "${RED}Failed to unmount /dev/$part. Exiting...${NC}"
                exit 2
            fi
            has_mounted=true
        fi
    done

    if sudo findmnt "$device" > /dev/null 2>&1; then
        echo "$device is mounted. Attempting to unmount..."
        sudo umount "$device" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully unmounted $device.${NC}"
        else
            echo -e "${RED}Failed to unmount $device. Exiting...${NC}"
            exit 2
        fi
        has_mounted=true
    fi

    if [ "$has_mounted" = false ]; then
        echo -e "${GREEN}No partitions were mounted on $device. Continuing...${NC}"
    fi
}

echo "=== UNIVERSAL USB BOOTABLE CREATOR ==="

# --- Double confirmation to avoid accidental wipes ---
read -p "This operation will erase your USB. Are you sure? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborted."
    exit 0
fi
read -p "Are you absolutely sure? This cannot be undone. (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Ask the user to select the USB device interactively ---
echo "Please select the USB device you want to format and write the ISO to:"
usb=$(select_usb_device) || exit 1

# --- Confirm the device again ---
read -p "You selected '$usb'. Are you sure? This will completely erase it. (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Unmount any mounted partitions of the USB ---
echo "Unmounting all partitions of $usb..."
check_mounted "$usb"

# --- Wipe the USB drive completely ---
echo "Wiping the USB drive.. This may take a few seconds..."
wipe_device "$usb"

# --- Format the new partition as FAT32 ---
echo "Formatting the partition as FAT32..."
sudo mkfs.vfat -F 32 "${usb}1"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully formatted the partition as FAT32.${NC}"
else
    echo -e "${RED}Failed to format the partition. Exiting...${NC}"
    exit 6
fi

# --- Ask for the ISO file path ---
read -e -p "Enter the full path to the ISO file: " iso

# --- Check that the ISO file exists ---
if [ ! -f "$iso" ]; then
    echo -e "${RED}ISO file not found at: $iso${NC}"
    exit 5
fi

# --- Check if the file is a valid ISO ---
echo "Checking if the file is a valid ISO..."
if ! file "$iso" | grep -q "ISO 9660"; then
    echo -e "${YELLOW}Warning: The file doesn't appear to be a standard ISO image.${NC}"
    read -p "Continue anyway (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# --- Write the ISO to the USB device using dd ---
echo "Writing the ISO to the USB device..."
sudo dd if="$iso" of="$usb" bs=4M conv=fdatasync status=progress

if [ $? -eq 0 ]; then
    echo -e "${GREEN}USB bootable drive created successfully!${NC}"
else
    echo -e "${RED}Something went wrong while writing the ISO.${NC}"
    exit 7
fi

# --- Attempt to mount the USB drive after writing ---
echo "🔄 Attempting to mount the USB drive..."

# --- Detect the real user who executed the script with sudo ---
if [ -n "$SUDO_USER" ]; then
    user_name="$SUDO_USER"
else
    user_name=$(whoami)
fi

# --- Detect the most common mount path ---
if [ -d "/media/$user_name" ]; then
    mount_point="/media/$user_name/usbdrive"
elif [ -d "/run/media/$user_name" ]; then
    mount_point="/run/media/$user_name/usbdrive"
else
    mount_point="/mnt/usbdrive"
fi

# --- Create the mount point if it does not exist ---
sudo mkdir -p "$mount_point"

# --- Attempt to mount the newly created partition (usually /dev/sdX1) ---
if sudo mount "${usb}1" "$mount_point"; then
    echo -e "${GREEN}USB drive mounted successfully at $mount_point.${NC}"
else
    echo -e "${RED}Failed to mount the USB drive. You may need to mount it manually.${NC}"
fi

