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

# Descargar imagen VirtIO desde bit.ly
wget -O virtio.iso https://bit.ly/4d1g7Ht

# Verificar si se descargó mal (menos de 1MB = falló)
iso_size=$(stat -c %s virtio.iso)
if [ "$iso_size" -lt 1048576 ]; then
    echo "⚠️ Descarga desde bit.ly falló o incompleta. Descargando desde mirror alternativo..."
    wget -O virtio.iso https://releases.pagure.org/virtio-win/virtio-win.iso
fi

# Montar virtio.iso y copiar los drivers al boot.wim
mkdir /root/virtio_mount
mount -o loop virtio.iso /root/virtio_mount

mkdir /mnt/sources/virtio_drivers
cp -r /root/virtio_mount/* /mnt/sources/virtio_drivers/

# Inyectar drivers al entorno del instalador
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
