#!/bin/bash
set -ex

yum install -y git python3


# update symbolic link to Python3 
#ln -sf /bin/python3 /bin/python
gal_dir=/shared/Galaxy/galaxy-app


# Define a cluster user (Cycle Cluster Owner) and start/install Galaxy
if -f /opt/cycle/jetpack/bin/jetpack; then
  sge_user=$(jetpack config cyclecloud.cluster.user.name)
else
  sge_user=cycleadmin
fi
mkdir -p /shared/Galaxy
chown -R ${sge_user}:${sge_user} /shared/Galaxy


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
if [ ! -d ${gal_dir} ]; then
  runuser -l ${sge_user} -c 'git clone https://github.com/galaxyproject/galaxy.git ${gal_dir}'
fi


# Copy Galaxy config files from CycleCloud project dir to Galaxy config path
if -d ${CYCLECLOUD_SPEC_PATH}; then
  cp ${CYCLECLOUD_SPEC_PATH}/files/{galaxy.yml,job_conf.xml,auth_conf.xml} ${gal_dir}/config
else
  wget -O ${gal_dir}/config/galaxy.yml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/galaxy.yml?token=AF2OLBZQPTJOCYPRBTN2T33BM3KUI
  wget -O ${gal_dir}/config/auth_config.xml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/auth_conf.xml?token=AF2OLB5MB667BS3C4672MTTBM3KRI 
  wget -O ${gal_dir}/config/job_config.xml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/job_conf.xml?token=AF2OLBZPJKTAHMOWQNQAIDLBM3KWU
fi


chown ${sge_user}:${sge_user} ${gal_dir}/config/{galaxy.yml,job_conf.xml,auth_conf.xml}


# register Galaxy server as SGE submit node IF deployed by CycleCloud
if -d /opt/cycle; then
  submitter=$(hostname -f)
  runuser -l ${sge_user} -c "ssh ${sge_user}@${sge_ip} 'sudo -i qconf -as ${submitter}'"
fi


# Start Galaxy as a daemon with galaxy.log file
if -d ${CYCLECLOUD_SPEC_PATH}; then
  jetpack log 'Galaxy startup begun'
  runuser -l ${sge_user} -c 'GALAXY_LOG=${gal_dir}/galaxy.log nohup sh ${gal_dir}/run.sh --daemon > \
    ${gal_dir}/galaxy.log 2>&1; sudo -i jetpack log "Galaxy daemon started"' &
else
  runuser -l ${sge_user} -c 'GALAXY_LOG=${gal_dir}/galaxy.log sh ${gal_dir}/run.sh --daemon'
fi
