# Universal USB Bootable Creator

## Description
This script allows you to format a USB drive and write an ISO file to it, making it bootable using the traditional `dd` method. It is designed to be simple and interactive, guiding the user through the process step by step.

## Features
- Detects connected USB devices.
- Wipes existing filesystem signatures and creates a new partition table.
- Formats the USB drive as FAT32.
- Writes an ISO file to the USB drive using `dd`.
- Attempts to mount the USB drive after writing.

## Requirements
- A Linux-based operating system.
- Root privileges (`sudo`).
- The following tools installed:
  - `lsblk`
  - `wipefs`
  - `fdisk`
  - `mkfs.vfat`
  - `dd`
  - `file`

## Usage
1. Clone or download this repository.
2. Open a terminal and navigate to the directory containing the script.
3. Run the script with root privileges:
   ```bash
   sudo ./universal-usb-booter.sh