#!/bin/bash

# Actualizar sistema e instalar paquetes necesarios
apt update -y && apt upgrade -y
apt install grub2 wimtools ntfs-3g libguestfs-tools wget rsync -y

# Obtener tamaño del disco y calcular particiones
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))
part_size_mb=$((disk_size_mb / 4))

# Crear tabla GPT y particiones
parted /dev/sda --script -- mklabel gpt
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB $((2 * part_size_mb))MB

# Reconocer particiones nuevas
partprobe /dev/sda
sleep 5
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

# Corregir tabla de particiones para GRUB
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda

# Montar particiones
mount /dev/sda1 /mnt
mkdir ~/windisk
mount /dev/sda2 ~/windisk

# Instalar GRUB
grub-install --root-directory=/mnt /dev/sda

# Crear entrada GRUB para iniciar instalador de Windows
cat <<EOF > /mnt/boot/grub/grub.cfg
menuentry "windows installer" {
	insmod ntfs
	search --set=root --file=/bootmgr
	ntldr /bootmgr
	boot
}
EOF

# Descargar ISO de Windows
cd ~/windisk
wget -O win10.iso --user-agent="Mozilla/5.0" https://bit.ly/3UGzNcB

mkdir winfile
mount -o loop win10.iso winfile

# Copiar contenido de Windows a la partición booteable
rsync -avz --progress winfile/* /mnt
umount winfile

# Descargar VirtIO ISO
wget -O virtio.iso https://bit.ly/4d1g7Ht

# Montar VirtIO ISO y copiar los drivers
mkdir /root/virtio_mount
mount -o loop virtio.iso /root/virtio_mount

mkdir /mnt/sources/virtio_drivers
cp -r /root/virtio_mount/* /mnt/sources/virtio_drivers/

# Agregar los drivers al boot.wim (índice 2)
cd /mnt/sources
echo 'add virtio_drivers /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Limpiar
umount /root/virtio_mount

# Finalizar
sync
echo "Todo listo. Reiniciando en 10s..."
sleep 10
reboot
