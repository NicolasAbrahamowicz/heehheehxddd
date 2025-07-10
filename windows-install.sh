#!/bin/bash

# Actualizar sistema e instalar herramientas necesarias
apt update -y && apt upgrade -y
apt install grub2 wimtools ntfs-3g wget rsync -y

# Calcular tamaño del disco y dividir en 2 particiones
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))
part_size_mb=$((disk_size_mb / 4))

# Crear tabla GPT y particiones NTFS
parted /dev/sda --script -- mklabel gpt
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB $((2 * part_size_mb))MB

# Forzar reconocimiento de las particiones
partprobe /dev/sda
sleep 5

# Formatear particiones
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

# Corregir tabla para que grub pueda instalarse bien
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda

# Montar la partición de arranque
mount /dev/sda1 /mnt

# Preparar carpeta para segunda partición
mkdir ~/windisk
mount /dev/sda2 ~/windisk

# Instalar GRUB en la primera partición
grub-install --root-directory=/mnt /dev/sda

# Crear archivo de configuración GRUB para bootear Windows
cat <<EOF > /mnt/boot/grub/grub.cfg
menuentry "windows installer" {
	insmod ntfs
	search --set=root --file=/bootmgr
	ntldr /bootmgr
	boot
}
EOF

# Descargar imagen ISO de Windows 10
cd ~/windisk
wget -O win10.iso --user-agent="Mozilla/5.0" https://bit.ly/3UGzNcB

# Montar ISO de Windows y copiar contenido al disco
mkdir winfile
mount -o loop win10.iso winfile
rsync -avz --progress winfile/* /mnt
umount winfile

# Descargar ISO de VirtIO desde Fedora (versión 0.1.240)
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso -O virtio.iso

# Montar ISO de VirtIO y copiar drivers
mkdir /root/virtio_mount
mount -o loop virtio.iso /root/virtio_mount

mkdir /mnt/sources/virtio_drivers
cp -r /root/virtio_mount/* /mnt/sources/virtio_drivers/

# Inyectar los drivers al entorno del instalador
cd /mnt/sources
echo 'add virtio_drivers /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Desmontar y limpiar
umount /root/virtio_mount
sync

# Reiniciar el VPS
echo "✅ Setup listo. Reboot en 10 segundos..."
sleep 10
reboot
