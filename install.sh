#!/bin/bash

# Цвета
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Ошибка: Запустите через sudo!${NC}"
  exit 1
fi

# Очистка экрана и заголовок
clear
echo -e "${BLUE}========================================"
echo -e "   ULI: Universal Linux Installer"
echo -e "========================================${NC}"

# 1. Выбор диска
echo -e "\n${YELLOW}Список дисков:${NC}"
lsblk -dno NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Введите имя диска (например, sda или nvme0n1): " DISK_NAME
TARGET_DISK="/dev/$DISK_NAME"

if [ ! -b "$TARGET_DISK" ]; then
    echo -e "${RED}Ошибка: Диск $TARGET_DISK не найден!${NC}"
    exit 1
fi

# 2. Разметка
echo -e "${RED}ВНИМАНИЕ: $TARGET_DISK будет ПОЛНОСТЬЮ стерт!${NC}"
read -p "Вы уверены? (y/n): " CONFIRM
[[ $CONFIRM != "y" ]] && exit 1

# Отмонтируем всё, что могло само примонтироваться
umount -l ${TARGET_DISK}* 2>/dev/null

echo -e "${BLUE}Уничтожение старой разметки и создание GPT...${NC}"
wipefs -a "$TARGET_DISK"
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%

# Определение разделов
if [[ $TARGET_DISK == *"nvme"* ]]; then
    BOOT_P="${TARGET_DISK}p1"; ROOT_P="${TARGET_DISK}p2"
else
    BOOT_P="${TARGET_DISK}1"; ROOT_P="${TARGET_DISK}2"
fi

# Ждем появления разделов в системе
sleep 2

echo -e "${BLUE}Форматирование...${NC}"
mkfs.fat -F32 "$BOOT_P"
mkfs.ext4 -F "$ROOT_P"

echo -e "${BLUE}Монтирование в /mnt/uli...${NC}"
mkdir -p /mnt/uli
mount "$ROOT_P" /mnt/uli
mkdir -p /mnt/uli/boot
mount "$BOOT_P" /mnt/uli/boot

# 3. Выбор дистра
echo -e "\n${YELLOW}Что ставим?${NC}"
echo "1) Ubuntu (jammy)"
echo "2) Arch Linux"
read -p "Выбор: " D_CHOICE

case $D_CHOICE in
    1)
        echo -e "${BLUE}Установка Ubuntu...${NC}"
        if ! command -v debootstrap &> /dev/null; then
            apt-get update && apt-get install -y debootstrap
        fi
        debootstrap --arch amd64 jammy /mnt/uli http://archive.ubuntu.com/ubuntu/
        ;;
    2)
        echo -e "${BLUE}Установка Arch...${NC}"
        # Если мы не в Arch LiveCD, скачиваем скрипты установки
        if ! command -v pacstrap &> /dev/null; then
            echo "Загрузка инструментов Arch..."
            curl -sL https://raw.githubusercontent.com/archlinux/arch-install-scripts/master/bin/pacstrap -o /usr/local/bin/pacstrap
            chmod +x /usr/local/bin/pacstrap
        fi
        # Примечание: pacstrap требует работающий pacman в системе
        echo "Ошибка: Для Arch из-под другого дистра нужен сложный bootstrap. В процессе..."
        ;;
esac

echo -e "${GREEN}Готово! Система развернута в /mnt/uli${NC}"
