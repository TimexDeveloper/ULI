#!/bin/bash

# Colors
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Please run as root (sudo)${NC}"
  exit 1
fi

clear
echo -e "${BLUE}========================================"
echo -e "   ULI: Universal Linux Installer"
echo -e "========================================${NC}"

# 1. Select Disk
echo -e "\n${YELLOW}Available drives:${NC}"
lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Enter disk name (e.g., sda or nvme0n1): " DISK_NAME
TARGET_DISK="/dev/$DISK_NAME"

if [ ! -b "$TARGET_DISK" ]; then
    echo -e "${RED}Error: Disk $TARGET_DISK not found!${NC}"
    exit 1
fi

# 2. Partitioning
echo -e "${RED}WARNING: ALL DATA ON $TARGET_DISK WILL BE DELETED!${NC}"
read -p "Are you sure? (y/n): " CONFIRM
[[ $CONFIRM != "y" ]] && exit 1

echo -e "${BLUE}Cleaning disk and creating GPT...${NC}"
umount -l ${TARGET_DISK}* 2>/dev/null
wipefs -a "$TARGET_DISK"

parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

# Partition detection
if [[ $TARGET_DISK == *"nvme"* ]]; then
    BOOT_P="${TARGET_DISK}p1"; ROOT_P="${TARGET_DISK}p2"
else
    BOOT_P="${TARGET_DISK}1"; ROOT_P="${TARGET_DISK}2"
fi

sleep 2
mkfs.fat -F32 "$BOOT_P"
mkfs.ext4 -F "$ROOT_P"

# 3. Mounting
mkdir -p /mnt/uli
mount "$ROOT_P" /mnt/uli
mkdir -p /mnt/uli/boot
mount "$BOOT_P" /mnt/uli/boot

# 4. Distribution Choice
echo -e "\n${YELLOW}Choose OS to install:${NC}"
echo "1) Ubuntu (jammy)"
echo "2) Arch Linux"
read -p "Selection: " D_CHOICE

case $D_CHOICE in
    1)
        echo -e "${BLUE}Installing Ubuntu (this may take 5-10 min)...${NC}"
        if ! command -v debootstrap &> /dev/null; then
            apt-get update && apt-get install -y debootstrap
        fi
        # Реальный процесс установки
        debootstrap --arch amd64 jammy /mnt/uli http://archive.ubuntu.com/ubuntu/
        ;;
    2)
        echo -e "${BLUE}Installing Arch Linux...${NC}"
        # Проверяем наличие pacman (если мы не в Arch LiveCD, это сложно)
        if command -v pacman &> /dev/null; then
            pacstrap /mnt/uli base linux linux-firmware
        else
            echo -e "${RED}Error: Arch installation requires pacman in the current LiveCD.${NC}"
            exit 1
        fi
        ;;
esac

# 5. Result check
if [ -f "/mnt/uli/etc/hostname" ] || [ -d "/mnt/uli/bin" ]; then
    echo -e "\n${GREEN}SUCCESS! System files deployed to /mnt/uli${NC}"
    echo -e "${YELLOW}Next step: chroot /mnt/uli to set password and grub.${NC}"
else
    echo -e "\n${RED}INSTALLATION FAILED: Files not found in /mnt/uli${NC}"
fi
