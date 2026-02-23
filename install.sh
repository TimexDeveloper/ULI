#!/bin/bash

# Цветовое оформление
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

# Проверка на root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Ошибка: Скрипт должен быть запущен от root (sudo)${NC}"
  exit 1
fi

clear
echo -e "${BLUE}========================================"
echo -e "   ULI: Universal Linux Installer"
echo -e "========================================${NC}"

# Функция выбора диска
select_disk() {
    echo -e "\n${YELLOW}Доступные накопители:${NC}"
    lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
    echo ""
    read -p "Введите имя диска (например, sda или nvme0n1): " DISK_NAME
    TARGET_DISK="/dev/$DISK_NAME"

    if [ ! -b "$TARGET_DISK" ]; then
        echo -e "${RED}Ошибка: Устройство $TARGET_DISK не найдено!${NC}"
        exit 1
    fi
}

# Функция разметки (базовая GPT/EFI)
prepare_disk() {
    echo -e "${YELLOW}ВНИМАНИЕ: Все данные на $TARGET_DISK будут удалены!${NC}"
    read -p "Продолжить? (y/N): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then exit 1; fi

    echo -e "${BLUE}Разметка диска...${NC}"
    # Создание таблицы GPT и разделов: 512MB EFI, остальное Root
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

    # Определение имен разделов (учет nvme)
    if [[ $TARGET_DISK == *"nvme"* ]]; then
        BOOT_PART="${TARGET_DISK}p1"
        ROOT_PART="${TARGET_DISK}p2"
    else
        BOOT_PART="${TARGET_DISK}1"
        ROOT_PART="${TARGET_DISK}2"
    fi

    echo -e "${BLUE}Форматирование разделов...${NC}"
    mkfs.fat -F32 "$BOOT_PART"
    mkfs.ext4 -F "$ROOT_PART"

    echo -e "${BLUE}Монтирование...${NC}"
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
}

# Меню выбора дистрибутива
echo -e "\nВыберите систему для установки:"
echo "1) Ubuntu (через debootstrap)"
echo "2) Arch Linux (через pacstrap)"
echo "3) NixOS (через nixos-install)"
echo "4) Gentoo (через stage3)"
echo "5) Выход"
read -p "Ваш выбор: " DISTRO_CHOICE

case $DISTRO_CHOICE in
    1)
        select_disk
        prepare_disk
        echo -e "${GREEN}Начинаю установку Ubuntu...${NC}"
        apt update && apt install -y debootstrap
        debootstrap --arch amd64 jammy /mnt http://archive.ubuntu.com/ubuntu/
        echo -e "${GREEN}Базовая система Ubuntu готова в /mnt${NC}"
        ;;
    2)
        select_disk
        prepare_disk
        echo -e "${GREEN}Начинаю установку Arch Linux...${NC}"
        # Проверка наличия pacstrap в Live-системе
        if ! command -v pacstrap &> /dev/null; then
            echo -e "${YELLOW}pacstrap не найден. Пытаюсь загрузить скрипты...${NC}"
            git clone https://archlinux.org/arch-install-scripts /tmp/arch-scripts
            export PATH=$PATH:/tmp/arch-scripts
        fi
        pacstrap /mnt base linux linux-firmware
        genfstab -U /mnt >> /mnt/etc/fstab
        echo -e "${GREEN}Базовая система Arch готова в /mnt${NC}"
        ;;
    3)
        echo -e "${YELLOW}Установка NixOS требует наличия Nix в текущей сессии.${NC}"
        # Здесь будет логика загрузки бинарного файла nix
        ;;
    4)
        echo -e "${YELLOW}Для Gentoo требуется загрузка stage3. В разработке...${NC}"
        ;;
    5)
        exit 0
        ;;
    *)
        echo "Неверный ввод."
        ;;
esac

echo -e "\n${BLUE}========================================"
echo -e "   Установка базовых файлов завершена!"
echo -e "   Используйте 'chroot /mnt' для настройки."
echo -e "========================================${NC}"
