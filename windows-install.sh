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

# 🔁 INTENTO 1: Descargar VirtIO desde bit.ly
wget -O virtio.iso https://bit.ly/4d1g7Ht

# Verificar tamaño
iso_size=$(stat -c %s virtio.iso)
if [ "$iso_size" -lt 1048576 ]; then
    echo "⚠️ bit.ly falló, probando con Fedora..."

    # 🔁 INTENTO 2: Descargar desde Fedora
    wget -O virtio.iso https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso

    iso_size=$(stat -c %s virtio.iso)
    if [ "$iso_size" -lt 1048576 ]; then
        echo "❌ Fedora falló, probando con Google Drive..."

        # 🔁 INTENTO 3: Descargar desde Google Drive
        wget -O virtio.iso --no-check-certificate "https://drive.usercontent.google.com/download?export=download&id=18sLSbOqWfQwpT6TA240EI2dROTgsFfcf&confirm=t"

        iso_size=$(stat -c %s virtio.iso)
        if [ "$iso_size" -lt 1048576 ]; then
            echo "🚨 Todas las descargas fallaron. Abortando..."
            exit 1
        else
            echo "✅ Descargado desde Google Drive con éxito."
        fi
    else
        echo "✅ Descargado desde Fedora con éxito."
    fi
else
    echo "✅ Descargado desde bit.ly con éxito."
fi

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
