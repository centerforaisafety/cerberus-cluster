#!/bin/bash


sudo mkdir /data/nodes_local
sudo chmod 700 /data/nodes_local

# execute commands on the remote host
for hostname in $(cat weka_hosts)
do
        echo "Processing $hostname"
        ssh -t $hostname "
        sudo umount /mnt/localdisk*
        sudo rm -r /mnt/localdisk*
        sudo mkdir /data/nodes_local/$hostname
        sudo chmod 700 /data/nodes_local/$hostname
        sudo mkdir /mnt/localdisk
        sudo mount --bind /data/nodes_local/$hostname /mnt/localdisk
        sudo mkdir /mnt/localdisk/enroot
        sudo mkdir /mnt/localdisk/enroot/enroot_tmp
        sudo mkdir /mnt/localdisk/enroot/enroot_cache
        sudo mkdir /mnt/localdisk/enroot/enroot_runtime
        sudo mkdir /mnt/localdisk/enroot/enroot_data
        sudo mkdir /mnt/localdisk/slurm_tmp
        sudo chown -R opc:privilege /mnt/localdisk/enroot
        sudo chown -R root:slurm /mnt/localdisk/slurm_tmp
        sudo chmod -R 770 /mnt/localdisk/slurm_tmp
        sudo chmod -R 777 /mnt/localdisk/enroot
        sudo sed -i '\%^LABEL=localscratch /mnt/localdisk/ xfs defaults,noatime 0 0$%d' /etc/fstab
        sudo sed -i '\%^LABEL=locscratch[0-9] /mnt/localdisk xfs defaults,noatime 0 0$%d' /etc/fstab
	echo '/data/nodes_local/$hostname /mnt/localdisk none defaults,bind 0 0' | sudo tee -a /etc/fstab
    "
done < weka_hosts
