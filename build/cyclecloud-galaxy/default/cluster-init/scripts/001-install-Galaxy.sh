#!/bin/bash
set -ex

yum install -y git python3


# update symbolic link to Python3 
#ln -sf /bin/python3 /bin/python


# set local DRMAA environment variable
if ! grep -qi "DRMAA_LIBRARY_PATH" /etc/profile; then
  echo "export DRMAA_LIBRARY_PATH=/sched/sge/sge-2011.11/lib/linux-x64/libdrmaa.so" >> /etc/profile
fi
source /etc/profile


# if /datasets (ALDS-NFS) is owned by root, reset permissions
if [ -O /datasets ]; then
  chown nobody:nobody /datasets
  chmod 1777 /datasets
fi


# set permissions of local SSD (cache_dir)
chmod 1777 /mnt/resource


# CLone the Galaxy repo to shared NFS dir (/shared)
if [ ! -d /shared/Galaxy/galaxy-app ]; then
  git clone https://github.com/galaxyproject/galaxy.git /shared/Galaxy/galaxy-app
fi


# Copy Galaxy config files from CycleCloud project dir to Galaxy config path
cp $CYCLECLOUD_SPEC_PATH/files/{galaxy.yml,job_conf.xml,auth_conf.xml} /shared/Galaxy/galaxy-app/config
chown $user:$user /shared/Galaxy/galaxy-app/config/{galaxy.yml,job_conf.xml,auth_conf.xml}


# Define a cluster user (Cycle Cluster Owner), create virtualenv and start/install Galaxy
user=$(jetpack config cyclecloud.cluster.user.name)
#pip3 install --user virtualenv
#/bin/python3 -m virtualenv /shared/Galaxy/galaxy_env
chown -R $user:$user /shared/Galaxy
runuser -l $user -c 'GALAXY_LOG=/shared/Galaxy/galaxy-app/galaxy.log sh /shared/Galaxy/galaxy-app/run.sh --daemon'


# register Galaxy server as SGE submit node
user=$(jetpack config cyclecloud.cluster.user.name)
submitter=$(jetpack config cyclecloud.instance.hostname)
scheduler=$(jetpack config cyclecloud.mounts.nfs_sched.address)
runuser -l $user -c "ssh $user@$scheduler 'sudo -i qconf -as $submitter'"