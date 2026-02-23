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

# 1. Select Disk (Исправленный ввод через /dev/tty)
echo -e "\n${YELLOW}Available drives:${NC}"
lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
echo ""

# Магия для curl | bash: читаем ввод прямо из терминала
echo -n "Enter disk name (e.g. sda or nvme0n1): "
read INPUT_DISK < /dev/tty

DISK_NAME=$(echo "$INPUT_DISK" | sed 's|/dev/||' | xargs)
TARGET_DISK="/dev/$DISK_NAME"

# Проверка через lsblk (самый надежный способ в Linux)
if ! lsblk "$TARGET_DISK" >/dev/null 2>&1; then
    echo -e "${RED}Error: Device $TARGET_DISK not found!${NC}"
    echo "Check the name and try again."
    exit 1
fi

echo -e "${GREEN}Found device: $(lsblk -dno MODEL "$TARGET_DISK")${NC}"

# 2. Partitioning
echo -e "${RED}WARNING: ALL DATA ON $TARGET_DISK WILL BE DELETED!${NC}"
echo -n "Are you sure? (y/n): "
read CONFIRM < /dev/tty
[[ $CONFIRM != "y" ]] && exit 1

echo -e "${BLUE}Preparing disk...${NC}"
umount -l ${TARGET_DISK}* 2>/dev/null || true
swapoff -a || true
wipefs -a "$TARGET_DISK"

# Разметка
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

udevadm settle

# Определение разделов
if [[ $TARGET_DISK == *"nvme"* ]] || [[ $TARGET_DISK == *"mmcblk"* ]]; then
    BOOT_P="${TARGET_DISK}p1"; ROOT_P="${TARGET_DISK}p2"
else
    BOOT_P="${TARGET_DISK}1"; ROOT_P="${TARGET_DISK}2"
fi

echo -e "${BLUE}Formatting $BOOT_P and $ROOT_P...${NC}"
mkfs.fat -F32 "$BOOT_P"
mkfs.ext4 -F "$ROOT_P"

# 3. Mounting
echo -e "${BLUE}Mounting...${NC}"
mkdir -p /mnt/uli
mount "$ROOT_P" /mnt/uli
mkdir -p /mnt/uli/boot
mount "$BOOT_P" /mnt/uli/boot

# 4. Distribution Choice
echo -e "\n${YELLOW}Choose OS to install:${NC}"
echo "1) Ubuntu (jammy)"
echo "2) Arch Linux"
echo "3) NixOS"
echo -n "Selection: "
read D_CHOICE < /dev/tty

case $D_CHOICE in
    1)
        echo -e "${BLUE}Installing Ubuntu...${NC}"
        if ! command -v debootstrap &> /dev/null; then
            apt-get update && apt-get install -y debootstrap
        fi
        debootstrap --arch amd64 jammy /mnt/uli http://archive.ubuntu.com/ubuntu/
        ;;
    2)
        echo -e "${BLUE}Installing Arch Linux...${NC}"
        if command -v pacman &> /dev/null; then
            pacstrap /mnt/uli base linux linux-firmware
        else
            echo -e "${RED}Error: Host system must be Arch-based for pacstrap.${NC}"
            exit 1
        fi
        ;;
    3)
        echo -e "${YELLOW}NixOS installation is complex. Deploying base structure...${NC}"
        # Для NixOS нужна генерация конфига
        ;;
esac

# 5. Finalize
if [ -d "/mnt/uli/bin" ] || [ -d "/mnt/uli/usr/bin" ]; then
    echo -e "\n${GREEN}SUCCESS! System deployed to /mnt/uli${NC}"
else
    echo -e "\n${RED}FAILED: Installation did not complete.${NC}"
fi
