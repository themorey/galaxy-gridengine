#!/bin/bash
set -ex

# Set SELinux to permissive
setenforce 0 
sed -i 's/enforcing/permissive/g' /etc/selinux/config


#Install Python3 and Packages
yum install -y git python3
runuser -l ${sge_user} -c "python3 -m pip install -U --user pip"
runuser -l ${sge_user} -c "python3 -m pip install --user virtualenv setuptools_rust cloudauthz"


# Set Galaxy install directory to NFS (/shared)
gal_dir=/shared/Galaxy


# Define a cluster user (Cycle Cluster Owner) and start/install Galaxy
if [ -f /opt/cycle/jetpack/bin/jetpack ]; then
  sge_user=$(jetpack config cyclecloud.cluster.user.name)
else
  sge_user=cycleadmin
fi
mkdir -p ${gal_dir}
if [[ $(stat -c '%U' ${gal_dir}) == ${sge_user} ]]; then
  echo "skipping...Galaxy dir already owned by ${sge_user}"
else
  chown -R ${sge_user}:${sge_user} ${gal_dir}
fi


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
if [ ! -f ${gal_dir}/run.sh ]; then
  runuser -l ${sge_user} -c "git clone https://github.com/galaxyproject/galaxy.git ${gal_dir}"
fi


# Copy Galaxy config files from CycleCloud project dir to Galaxy config path
if [ ! -f ${gal_dir}/config/auth_conf.xml ]; then
  if [ -d ${CYCLECLOUD_SPEC_PATH} ]; then
    cp ${CYCLECLOUD_SPEC_PATH}/files/{galaxy.yml,job_conf.xml,auth_conf.xml} ${gal_dir}/config
  else
    wget -O ${gal_dir}/config/galaxy.yml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/galaxy.yml
    wget -O ${gal_dir}/config/auth_config.xml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/auth_conf.xml
    wget -O ${gal_dir}/config/job_config.xml https://raw.githubusercontent.com/themorey/galaxy-gridengine/main/specs/default/cluster-init/files/job_conf.xml
  fi
fi

chown ${sge_user}:${sge_user} ${gal_dir}/config/{galaxy.yml,job_conf.xml,auth_conf.xml}


# register Galaxy server as SGE submit node IF deployed by CycleCloud
if [ -d /opt/cycle ]; then
  submitter=$(hostname -f)
  sge_ip=$(jetpack config cyclecloud.mounts.nfs_sched.address)
  runuser -l ${sge_user} -c "ssh ${sge_user}@${sge_ip} 'sudo -i qconf -as ${submitter}'"
fi


# Start Galaxy as a daemon with galaxy.log file
# if [ -d ${CYCLECLOUD_SPEC_PATH} ]; then
#  jetpack log 'Galaxy startup begun'
#  runuser -l ${sge_user} -c "GALAXY_LOG=${gal_dir}/galaxy.log nohup sh ${gal_dir}/run.sh --daemon \
#    > ${gal_dir}/galaxy.log 2>&1; sudo -i jetpack log 'Galaxy daemon started' " &
# else
#  runuser -l ${sge_user} -c "GALAXY_LOG=${gal_dir}/galaxy.log sh ${gal_dir}/run.sh --daemon"
# fi


# systemd service for Galaxy web without NGINX
cat <<EOF >>/etc/systemd/system/galaxy.service
[Unit]
Description=Galaxy
After=network.target
After=time-sync.target

[Service]
Environment="SGE_ROOT=${SGE_ROOT}"
Environment="SGE_CELL=${SGE_CELL}"
Environment="SGE_EXECD_PORT=${SGE_EXECD_PORT}"
Environment="SGE_QMASTER_PORT=${SGE_QMASTER_PORT}"
Environment="SGE_CLUSTER_NAME=${SGE_CLUSTER_NAME}"
UMask=022
User=${sge_user}
Group=${sge_user}
WorkingDirectory=${gal_dir}
ExecStart=/bin/sh -c '${gal_dir}/.venv/bin/uwsgi --yaml ${gal_dir}/config/galaxy.yml >> ${gal_dir}/galaxy.log 2>&1'
ExecStop=/bin/sh ${gal_dir}/run.sh --stop-daemon
Restart=always

[Install]
WantedBy=multi-user.target reboot.target
EOF

# systemd service for Galaxy with NGINX proxy
# cat <<EOF >>/etc/systemd/system/galaxy.service
# [Unit]
# Description=Galaxy
# After=network.target
# After=time-sync.target

# [Service]
# Environment="SGE_ROOT=${SGE_ROOT}"
# Environment="SGE_CELL=${SGE_CELL}"
# Environment="SGE_EXECD_PORT=${SGE_EXECD_PORT}"
# Environment="SGE_QMASTER_PORT=${SGE_QMASTER_PORT}"
# Environment="SGE_CLUSTER_NAME=${SGE_CLUSTER_NAME}"
# UMask=022
# Type=simple
# User=${sge_user}
# Group=${sge_user}
# WorkingDirectory=${gal_dir}
# ExecStart=/bin/sh -c '/shared/Galaxy/.venv/bin/uwsgi --yaml /shared/Galaxy/config/galaxy.yml > /shared/Galaxy/galaxy.log 2>&1'
# MemoryLimit=12G
# Restart=always

# MemoryAccounting=yes
# CPUAccounting=yes
# BlockIOAccounting=yes

# [Install]
# WantedBy=multi-user.target
# EOF

systemctl daemon-reload
systemctl enable galaxy.service
systemctl start galaxy.service


# Create a logrotate file
cat <<EOF >>/etc/logrotate.d/galaxy
${gal_dir}/galaxy.log {
  weekly
  rotate 8
  copytruncate
  compress
  missingok
  notifempty
}
EOF
