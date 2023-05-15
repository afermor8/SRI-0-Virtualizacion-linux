#!/bin/bash

# Comenzamos comprobando si existe la imagen base y si no la descargamos
echo "+-----------------------------------------------------------+"
echo "+------------COMENZANDO EJECUCIÓN DEL SCRIPT----------------+"
echo "+-----------------------------------------------------------+"
echo ""
echo "0. Comprobando si existe la imagen base"
echo "+------------------------------------------+"
echo ""
sleep 2

if [ ! -f bullseye-base-sparse.qcow2 ]; then
    echo "Imagen base no encontrada ❌"
    echo "Descargando paquete 'megatools'..."
    sudo apt update > /dev/null 2>&1
    sudo apt install megatools -y > /dev/null 2>&1
    echo ""
    echo "Paquete 'megatools' descargado correctamente ✅"
    echo ""
    echo "Descargando imagen base..."
    megadl https://mega.nz/file/EKJmQL7b#iQg-kTZSBS7Os7Gj6JvdaWCEEy__7oend-YqiqMNR74
    echo ""
    echo "Imagen base descargada correctamente ✅"
    echo ""
else
    echo "Imagen base encontrada ✅"
    echo ""
    sleep 2
fi

# Creamos la imagen 

echo "1. Comprobando si existe la imagen qcow2"
echo "+------------------------------------------+"
echo ""

if [ ! -f maquina1.qcow2 ]; then
    echo "Imagen maquina1.qcow2 no encontrada ❌"
    echo ""
    echo "--Creando imagen maquina1.qcow2--"
    echo ""
    qemu-img create -f qcow2 -b bullseye-base-sparse.qcow2 maquina1.qcow2 > /dev/null 2>&1
    sleep 1
    echo "maquina1 creada correctamente ✅"
    echo ""
    echo "--Redimensionando la imagen a 5GB--"
    echo "Esto puede tardar unos segundos..." 
    qemu-img resize maquina1.qcow2 5G > /dev/null
    sleep 2
    cp maquina1.qcow2 maquina1copia.qcow2
    sleep 2
    virt-resize --expand /dev/vda1 maquina1.qcow2 maquina1copia.qcow2 >/dev/null
    sleep 2
    rm maquina1.qcow2 && mv maquina1copia.qcow2 maquina1.qcow2
    sleep 1
    echo ""
    echo "Redimensionado correcto ✅"
    echo ""

else
    echo "Imagen maquina1.qcow2 encontrada ✅"
    echo ""
fi

# Creamos red interna llamada intra con salida al exterior (NAT() y direccionamiento 10.10.20.0/24.

echo "2. Comprobando si existe el fichero de red intra"
echo "+------------------------------------------+"
echo ""
sleep 2

if [ ! -f intra.xml ]; then
    echo "--Creando fichero intra.xml--"
    echo ""
    sleep 2

    # Comprobamos si somos root
    if [ "$EUID" -ne 0 ]
    then echo "¡¡ERROR!! Debes ejecutar el script como root. 🆘"
        exit
    else
        echo "  Creando fichero de configuración de la red intra..."
        echo "
<network>
  <name>intra</name>
  <bridge name='intra'/>
  <forward/>
  <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.10.20.2' end='10.10.20.254'/>
    </dhcp>
  </ip>
</network>
        " >> intra.xml
        echo ""
        echo "Fichero de configuración de la red intra creado correctamente ✅"
        echo ""
        sleep 10
    fi
else
    echo "Fichero de red intra.xml encontrado ✅"
    echo ""
fi


# Comprobamos si existe la red intra

echo "3. Comprobando si existe la red intra"
echo "+------------------------------------------+"
echo ""
sleep 2

if virsh -c qemu:///system net-list --all | grep "intra" > /dev/null; then
    echo "Red intra encontrada ✅"
    echo ""
else
    echo "Red intra no encontrada ❌"
    echo ""
    echo "--Creando red intra--"
    echo ""
    virsh net-define intra.xml > /dev/null
    virsh net-start intra > /dev/null
    virsh net-autostart intra > /dev/null
    echo "Red intra creada correctamente ✅"
    echo ""
    sleep 2
fi


# Creamos mv maquina1 conectada a red intra (1 GB de RAM, disco raíz maquina1.qcow2 y que se inicie automáticamente)
# Arrancamos la máquina y modificamos fichero /etc/hostname

echo "4. Comprobando si existe maquina1"
echo "+------------------------------------------+"
echo ""
sleep 2

virsh -c qemu:///system list --all | grep maquina1 >/dev/null
existemaquina=$?

if [ $existemaquina -ne 0 ]; then
    echo "Máquina virtual maquina1 no encontrada ❌"
    echo ""
    echo "--Creando maquina1--"
    virt-install --connect qemu:///system --virt-type kvm --name maquina1 --disk maquina1.qcow2 --os-variant debian10 --memory 1024 --vcpus 1 --network network=intra --autostart --import --noautoconsole >/dev/null
    virsh -c qemu:///system autostart maquina1 >/dev/null
    echo ""
    echo "maquina1 creada correctamente ✅"
    echo ""
    sleep 20

    ip=$(virsh -c qemu:///system domifaddr maquina1 | awk '{print $4}' | cut -d "/" -f 1 | sed -n 3p)
    echo "--IP de la máquina virtual maquina1: "$ip" "
    echo ""
    sleep 2
    echo "--Modificando el hostname de maquina1--"
    echo ""
    ssh-keyscan "$ip" >> ~/.ssh/known_hosts 2>/dev/null
    ssh -i clave debian@"$ip" "sudo hostnamectl set-hostname maquina1"
    echo "Modificación correcta ✅"
    echo ""
    sleep 2
    echo "--Reiniciando maquina1--"
    echo "Esto puede tardar unos segundos..."
    echo ""
    virsh -c qemu:///system reboot maquina1 >/dev/null
    sleep 30
else
    echo "Máquina virtual maquina1 encontrada ✅"
    echo ""
fi



# Creamos volumen adicional de 1 GB en formato RAW ubicado en el pool por defecto

echo "5. Comprobando si existe el volumen adicional"
echo "+------------------------------------------+"
echo ""
sleep 2

virsh -c qemu:///system vol-list default | grep adicional.raw >/dev/null
existevolumen=$?

if [ $existevolumen -ne 0 ]; then
    echo "Volumen adicional no encontrado ❌"
    echo ""
    echo "--Creando volumen adicional--"
    virsh -c qemu:///system vol-create-as default adicional.raw 1G >/dev/null
    echo "Volumen adicional creado ✅"
    echo ""
    sleep 2
else
    echo "Volumen adicional existe ✅"
    echo ""
fi


# Una vez iniciada la MV maquina1, conecta el volumen a la máquina, crea un sistema de ficheros XFS en el volumen y móntalo en el directorio /var/www/html. Ten cuidado con los propietarios y grupos que pongas, para que funcione adecuadamente el siguiente punto.

echo "6. Comprobando si existe el volumen vdb en maquina1"
echo "+------------------------------------------+"
echo ""
sleep 2

ip=$(virsh -c qemu:///system domifaddr maquina1 | awk '{print $4}' | cut -d "/" -f 1 | sed -n 3p)

ssh -i clave debian@"$ip" 'lsblk | grep vdb' >/dev/null
rawconectado=$?

if [ $rawconectado -ne 0 ]; then
    echo "Volumen vdb no existe ❌"
    echo ""
    sleep 2
    echo "--Conectando volumen adicional a la maquina maquina1--"
    echo ""
    virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/adicional.raw vdb --driver=qemu --type disk --subdriver raw --persistent >/dev/null
    echo "Volumen adicional conectado correctamente ✅"
    echo ""
    sleep 2

    echo "--Dando formato XFS al volumen--"
    echo ""
    ssh -i clave debian@"$ip" "sudo mkfs.xfs /dev/vdb" >/dev/null
    echo "Formateado correcto ✅"
    echo ""

    echo "--Montando el volumen en /var/www/html--"
    echo ""
    ssh -i clave debian@"$ip" 'sudo mkdir -p /var/www/html' 
    ssh -i clave debian@"$ip" "sudo mount /dev/vdb /var/www/html" >/dev/null 
    echo "Montado correctamente ✅"
    echo ""
    sleep 2

    echo "--Introduciendo en fstab el volumen vdb--"
    echo ""
    ssh -i clave debian@"$ip" "sudo -- bash -c 'echo "/dev/vdb        /var/www/html   xfs     defaults        0       0" >> /etc/fstab'"
    echo "Introducido correctamente ✅"
    echo ""
    sleep 2
else
    echo "Existe volumen vdb ✅"
    echo "" 
fi

# Instalamos apache2. Copiamos fichero index.html a maquina1.

echo "7. Comprobando si apache2 está instalado"
echo "+------------------------------------------+"
echo ""
sleep 2

if ssh -i clave debian@"$ip" "dpkg -l | grep apache2" >/dev/null; then
    echo "Apache2 está instalado ✅"
    echo ""
else
    echo "Apache2 no se encuentra instalado ❌"
    echo ""
    sleep 2

    echo "--Instalando apache2--"
    echo ""
    ssh -i clave debian@"$ip" "sudo apt update && sudo apt install apache2 -y" >/dev/null 2>&1
    echo "Instalado correctamente ✅"
    echo ""
    sleep 2

    echo "--Copiando index.html--"
    echo ""
    scp -i clave index.html debian@"$ip":/home/debian >/dev/null
    scp -i clave indy-leeloo.jpeg debian@"$ip":/home/debian >/dev/null
    ssh -i clave debian@"$ip" "sudo chown www-data:www-data /home/debian/index.html" >/dev/null
    ssh -i clave debian@"$ip" "sudo chown www-data:www-data /home/debian/indy-leeloo.jpeg" >/dev/null
    ssh -i clave debian@"$ip" "sudo mv /home/debian/index.html /var/www/html" >/dev/null
    ssh -i clave debian@"$ip" "sudo mv /home/debian/indy-leeloo.jpeg /var/www/html" >/dev/null
    echo "Copiado correctamente ✅"
    echo ""
    sleep 2
fi


# Mostramos la dirección IP de máquina1. Pausamos el script y comprobamos que podemos acceder a la página web.

echo "8. La dirección IP de la máquina virtual es: $ip "
echo "Puedes acceder a la página web en http://$ip"
echo "+------------------------------------------+"
echo ""
read -rp "Pulsa Enter para continuar el script..."
echo ""

# Instalamos LXC y creamos un linux container llamado container1.

echo "9. Comprobando si LXC está instalado "
echo "+------------------------------------------+"
echo ""
sleep 2
if ssh -i clave debian@"$ip" "dpkg -l | grep lxc" >/dev/null; then
    echo "LXC está instalado ✅"
    echo ""
else
    echo "LXC no está instalado ❌"
    echo ""
    sleep 2
    echo "--Instalando LXC--"
    echo ""
    ssh -i clave debian@"$ip" "sudo apt update && sudo apt install lxc -y" >/dev/null 2>&1
    echo "Instalado correctamente ✅"
    echo ""
    sleep 2

    echo "--Creando container1--"
    echo ""
    ssh -i clave debian@"$ip" 'sudo lxc-create -n container1 -t debian -- -r bullseye' >/dev/null 2>&1
    echo "Creado correctamente ✅"
    echo ""
    sleep 2
fi


# Añadimos nueva interfaz a maquina1 para conectarla a la red pública (al punte br0).

echo "10. Comprobando si la interfaz enp8s0 está creada "
echo "+------------------------------------------+"
echo ""
sleep 2

if ssh -i clave debian@"$ip" "ip a | grep enp8s0" >/dev/null; then
    echo "Interfaz enp8s0 creada ✅"
    echo ""

else
    echo "Interfaz enp8s0 no creada ❌"
    echo ""
    sleep 2

    echo "--Modificando /etc/network/interfaces--"
    echo ""
    ssh -i clave debian@"$ip" "sudo -- bash -c 'echo "">> /etc/network/interfaces'"
    ssh -i clave debian@"$ip" "sudo -- bash -c 'echo "auto enp8s0" >> /etc/network/interfaces'"
    ssh -i clave debian@"$ip" "sudo -- bash -c 'echo "iface enp8s0 inet dhcp" >> /etc/network/interfaces'"
    echo "Modificación correcta ✅"
    echo ""

    echo "--Apagando maquina1--"
    echo ""
    virsh -c qemu:///system shutdown maquina1 >/dev/null
    sleep 24

    echo "--Añadiendo br0--"
    echo ""
    virsh -c qemu:///system attach-interface --domain maquina1 --type bridge --source br0 --model virtio --persistent >/dev/null
    
    echo "--Encendiendo maquina1--"
    echo ""
    virsh -c qemu:///system start maquina1 >/dev/null
    sleep 60
    echo "--Levantando interfaz bridge--"
    echo ""
    ssh -i clave debian@"$ip" 'sudo ifup enp8s0' >/dev/null 2>&1
    echo "Interfaz levantada correctamente ✅"
    echo ""
fi


# Muestra la nueva IP que ha recibido.

ipbr=$(ssh -i clave debian@"$ip" 'ip a | grep inet | grep enp8s0 | awk "{print \$2}" | sed "s/...$//"')
echo "La nueva IP de la máquina virtual es: $ipbr "
echo ""

# Apagamos maquina1 y aumentamos la RAM a 2 GB. Iniciamos la máquina.

echo "11. Agregar a la RAM 2GB"
echo "+------------------------------------------+"
echo ""
echo "--Apagando maquina1--"
echo ""
virsh -c qemu:///system shutdown maquina1 >/dev/null
sleep 24
echo "--Aumentando RAM a 2GB--"
echo ""
virsh -c qemu:///system setmaxmem maquina1 2G --config >/dev/null
virsh -c qemu:///system setmem maquina1 2G --config >/dev/null
echo "--Encendiendo maquina1--"
echo ""
virsh -c qemu:///system start maquina1 >/dev/null
sleep 24
echo "RAM aumentada correctamente ✅"
echo ""

# Creamos un snapshot de la máquina virtual.

echo "12 Creando snapshot"
echo "+------------------------------------------+"
echo ""
virsh -c qemu:///system snapshot-create-as maquina1 --name snapshot-maquina1 --description "Snapshot de la MV maquina1" --disk-only --atomic >/dev/null
sleep 2
echo "Snapshot creado correctamente ✅"
echo ""

echo "+-----------------------------------------------------------+"
echo "+-------------------SCRIPT FINALIZADO-----------------------+"
echo "+-----------------------------------------------------------+"


## EXAMEN

# Apagar maquina1

virsh -c qemu:///system shutdown maquina1 >/dev/null

# Desconecto el volumen de 1 GB de maquina1

virsh -c qemu:///system detach-disk maquina1 vdb --persistent

# Creo una imagen nueva que utilice maquina1.qcow2 con imagen base y tenga 6GB de tamaño maximo. La imagen se llamará maquina2.qcow2

qemu-img create -f qcow2 -b maquina1.qcow2 maquina2.qcow2 6G
qemu-img resize maquina2.qcow2 6G

# Creo una nueva máquina virtual llamada maquina2 con la imagen maquina2.qcow2 conectada a la red intra con 1 GB de RAM

virt-install --connect qemu:///system --virt-type kvm --name maquina2 --disk maquina2.qcow2 --os-variant debian10 --memory 1024 --vcpus 1 --network network=intra --autostart --import --noautoconsole

# Asocio el volumen de 1 GB a la nueva maquina y comprueba que puedes acceder a la web
virsh -c qemu:///system attach-disk maquina2 /var/lib/libvirt/images/adicional.raw vdb --driver=qemu --type disk --subdriver raw --persistent





##EXAMEN. Virtualización Linux
#Pantallazos Prueba de Funcionamiento

10.png
11.png
12.png
13.png

#Modificación

#1. Instrucciones ejecutadas

virsh -c qemu:///system shutdown maquina1 >/dev/null
virsh -c qemu:///system detach-disk maquina1 vdb --persistent
qemu-img create -f qcow2 -b maquina1.qcow2 maquina2.qcow2 6G
qemu-img resize maquina2.qcow2 6G
virt-install --connect qemu:///system --virt-type kvm --name maquina2 --disk maquina2.qcow2 --os-variant debian10 --memory 1024 --vcpus 1 --network network=intra --autostart --import --noautoconsole
virsh -c qemu:///system attach-disk maquina2 /var/lib/libvirt/images/adicional.raw vdb --driver=qemu --type disk --subdriver raw --persistent

#También he cambiado el nombre de la maquina en /etc/hostname a maquina2.


#2. Salida del comando "qemu-img info maquina2.qcow2"

image: maquina2.qcow2
file format: qcow2
virtual size: 6 GiB (6442450944 bytes)
disk size: 25.1 MiB
cluster_size: 65536
backing file: maquina1.qcow2
backing file format: qcow2
Format specific information:
    compat: 1.1
    compression type: zlib
    lazy refcounts: false
    refcount bits: 16
    corrupt: false
    extended l2: false

#3. Ejecución del comando "df -h"

S.ficheros     Tamaño Usados  Disp Uso% Montado en
udev             465M      0  465M   0% /dev
tmpfs             97M   580K   96M   1% /run
/dev/vda1        4,1G   2,0G  2,1G  49% /
tmpfs            483M      0  483M   0% /dev/shm
tmpfs            5,0M      0  5,0M   0% /run/lock
/dev/vdb        1014M    40M  975M   4% /var/www/html
tmpfs             97M      0   97M   0% /run/user/1000

#4. Accediendo a la maquina se puede acceder al contenedor

debian@maquina2:~$ sudo lxc-start container1
debian@maquina2:~$ sudo lxc-attach container1
root@container1:/# ls
bin   dev  home  lib32	libx32	mnt  proc  run	 selinux  sys  usr
boot  etc  lib	 lib64	media	opt  root  sbin  srv	  tmp  var
root@container1:/# exit

#5. IP de la nueva maquina y acceso a la web

debian@maquina2:~$ ip -br a
lo               UNKNOWN        127.0.0.1/8 ::1/128 
enp1s0           UP             10.10.20.2/24 fe80::5054:ff:fee3:bd2e/64 
lxcbr0           DOWN           10.0.3.1/24

arantxa@tars:~/git/SRI-0-Virtualizacion-linux$ virsh -c qemu:///system domifaddr maquina2
 Nombre     dirección MAC       Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:e3:bd:2e    ipv4         10.10.20.2/24


16.png