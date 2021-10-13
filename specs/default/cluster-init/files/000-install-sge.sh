#!/bin/bash

set -ex


# ensure nfs pkg is installed
yum install -y nfs-util epel-release
yum install -y jq


# define/discover cluster info
cycle_user=galaxyuser
cycle_pass='AzureCloud2021!@'
cycle_url='https://cycle-80-scus.southcentralus.cloudapp.azure.com'
sge_cluster_name='jm-sge-galaxy-eus'
sge_user='jmorey'
sge_ip=$(curl -s -k --user "${cycle_user}:${cycle_pass}" \
  "${cycle_url}/clusters/${sge_cluster_name}/nodes" \
  | jq -r '.nodes[] | select(.Template=="scheduler") | .IpAddress')


# change/shorten the hostname
hostnamectl set-hostname 'Galaxy-VM'
hostnamectl


# Mount NFS exports from SGE qmaster
mkdir -p /{sched,shared}

if ! grep -q "${sge_ip}:/sched" /etc/fstab; then
    echo "${sge_ip}:/sched /sched nfs defaults 0 0" >> /etc/fstab
fi 
if ! grep -q "${sge_ip}:/shared" /etc/fstab; then
    echo "${sge_ip}:/shared /shared nfs defaults 0 0" >> /etc/fstab
fi
mount -a


# declare environment variables
ln -sf /sched/sge/sge-2011.11/default/common/settings.sh /etc/profile.d/sgesettings.sh
ln -sf /sched/sge/sge-2011.11/default/common/settings.csh /etc/profile.d/sgesettings.csh
ln -sf /sched/sge/sge-2011.11/default/common/settings.sh /etc/cluster-setup.sh
ln -sf /sched/sge/sge-2011.11/default/common/settings.csh /etc/cluster-setup.csh


# add sgeadmin group and user
if ! grep -q sgeadmin /etc/group; then
    groupadd --gid 536 sgeadmin
fi
if ! grep -q sgeadmin /etc/passwd; then
    useradd --uid 536 --gid sgeadmin --no-create-home sgeadmin
fi


# find uid/gid of cluster user and add user
if ! grep -q ${sge_user} /etc/password; then
    sge_user_id=$(ls -l /shared/home/ |grep ${sge_user} | cut -d " " -f3)
    useradd -b /shared/home -u ${sge_user_id} -U -M  ${sge_user}
fi


# register Galaxy server as SGE submit node
submitter=$(hostname -f)
runuser -l ${sge_user} -c "ssh ${sge_user}@${sge_ip} 'sudo -i qconf -ah ${submitter} && sudo -i qconf -as ${submitter}'"

#runuser -l ${cycle_user} -c "ssh ${cycle_user}@${qmaster_ip} 'sudo -i echo "$(hostname -I)  $(hostname)  $(hostname -f)" '"

# Run the SGE install script for a submit node
#sh /sched/inst_sge.sh -s

