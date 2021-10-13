# Galaxy server with GridEngine
========

This project will deploy a GridEngine cluster (Scheduler and Compute nodes) and a Galaxy server configured as a GrideEngine submitter node.  Galaxy will use the DRMAA Python API to submit jobs to SGE as configured in the provided config files (ie. `galaxy.yml`, `job_config.xml` & `auth_config.xml`).


## Cluster template file changes from default:
The following template configs will deploy the Galaxy server as s submit node and configure the cluster nodes with Python3 (`templates/gridengin-galaxy2.txt`)  


    [[node defaults]]
    
    CloudInit = '''#cloud-config
    runcmd:
    - yum install -y git python3
    - echo "export DRMAA_LIBRARY_PATH=/sched/sge/sge-2011.11/lib/linux-x64/libdrmaa.so" >> /etc/profile
    - source /etc/profile
    '''  
      
    [[node Galaxy]]
    MachineType = $GalaxyMachineType
    ImageName = $GalaxyImageName
    AdditionalClusterInitSpecs = $GalaxyClusterInitSpecs
    
        [[[configuration]]]
        run_list = recipe[cyclecloud::_hosts], recipe[cshared::client], recipe[cuser], recipe[gridengine::submitter]
        
        [[[cluster-init cyclecloud-galaxy:default:1.0.0]]]

        [[[network-interface eth0]]]
        AssociatePublicIpAddress = $GalaxyPublicNetwork

        [[[input-endpoint SSH]]]
        PrivatePort = 22

        [[[input-endpoint HTTP]]]
        PrivatePort = 8080  
        
        
        
   **(NOTE: There are also PARAMETERS config associated with the above that are not shown here but exist in the template)**  
 



## Cluster Specs
This project includes 3 Galaxy config files (`galaxy.yml`, `job_config.xml` & `auth_config.xml`) files that and a script named `001-install-Galaxy.sh`.  The `001-install-Galaxy.sh` script does the following:

- Installs Git & Python3 if needed  
- Defines the Galaxy install directory (`gal_dir`)  
- Finds (if CycleCloud aka CC deployed) or hardcodes a GridEngine user (`sge_user`)  
- Creates the Galaxy directory on the NFS `/shared` mount (if it doesn't exist)...this dir is mounted on each node in SGE cluster  
- Sets the `drmaa-python` library environment variable in all users profile  
- Sets owners and permissions for local SSD (`/mnt/resource`) and common data directory (`/datasets`)  
- Git clones the Galaxy repo to `gal_dir` (`/shared/Galaxy/galaxy-app`)  
- Copies the config files (`galaxy.yml, job_config.xml & auth_config.xml`) to the Galaxy install (`gal_dir`)  
- Adds the Galaxy server as a submitter node in SGE  
- Starts Galaxy as a daemon with `galaxy.log` located in `gal_dir`      



## Customization  
The provided config files provide default settings with the following assumptions:

   - Authentication is using the Galaxy localDB (`auth_conf.xml` & `galaxy.yml`)  
    - The Galaxy user submitting the job to SGE must exist in the SGE cluster  
    - CC provides a shared user environment for the cluster but uses passwordless auth....Galaxy requires password  
    - An external LDAP/AD (not AAD) could be deployed by CC to all the nodes in the cluster  
    - In this case the Galxay auth (`auth_conf.xml`) should be changed to PAM unless the external LDAP/AD is providing uid/gid info  
  - Cluster configuration (`job_conf.xml`)  
    - job parameters are set to the SGE default template with slot_types HTC and HPC defined  
    - This file needs to be updated if the Cluster config changes    


  ## How to use this CC project  
  
  **NOTE:** this project assumes you have a working CC VM deployed    
  
  
  - Git clone this project   
      `git clone https://github.com/themorey/galaxy-gridengine.git .`  
  
  - Upload project to CC locker  
        `cd galaxy-gridengine`  
        `# modify files (if needed)`  
        `cyclecloud project upload <locker_name>`  
        
  - Import cluster template to CC  
        `cyclecloud import_cluster Galaxy-Gridengine -c Galaxy -f templates/gridengine-galaxy2.txt`  
        
  - Navigate to CC Portal to configure & start the cluster
