#!/bin/bash

# Actualizar e instalar herramientas necesarias
apt update -y && apt upgrade -y
apt install grub2 wimtools ntfs-3g wget rsync -y

# Calcular tamaño del disco y particiones
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))
part_size_mb=$((disk_size_mb / 4))

# Crear tabla GPT y particiones
parted /dev/sda --script -- mklabel gpt
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB $((2 * part_size_mb))MB

# Reconocer particiones
partprobe /dev/sda
sleep 5

# Formatear particiones
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

# Reparar tabla con gdisk
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda

# Montar partición 1 (boot)
mount /dev/sda1 /mnt

# Preparar partición 2 (datos)
mkdir ~/windisk
mount /dev/sda2 ~/windisk

# Instalar GRUB
grub-install --root-directory=/mnt /dev/sda

# Crear entrada GRUB para bootear Windows
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

# Montar ISO de Windows y copiar archivos
mkdir winfile
mount -o loop win10.iso winfile
rsync -avz --progress winfile/* /mnt
umount winfile

# Descargar VirtIO drivers desde servidor propio (ngrok)
echo "📦 Descargando VirtIO desde servidor local (ngrok)..."
wget -O virtio.iso --no-check-certificate https://28c86d596cfb.ngrok-free.app/virtio-win-0.1.240.iso || {
    echo "❌ Falló la descarga desde tu servidor ngrok. Abortando..."
    exit 1
}

# Montar VirtIO y copiar drivers
mkdir /root/virtio_mount
mount -o loop virtio.iso /root/virtio_mount

mkdir /mnt/sources/virtio_drivers
cp -r /root/virtio_mount/* /mnt/sources/virtio_drivers/

# Inyectar drivers en el entorno de instalación
cd /mnt/sources
echo 'add virtio_drivers /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Desmontar y limpiar
umount /root/virtio_mount
sync

# Reiniciar el sistema
echo "✅ Todo listo. Reiniciando en 10 segundos..."
sleep 10
reboot
